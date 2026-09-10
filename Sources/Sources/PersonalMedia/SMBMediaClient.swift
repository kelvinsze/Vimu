import Foundation
import SMBClient

/// SMB2 media browser and player source. SMB1 is intentionally unsupported.
public final class SMBMediaClient: MediaServerProtocol, @unchecked Sendable {
    public let serverId: UUID
    public let serverName: String
    public let serverBaseURL: URL
    private let configuration: SMBPlaybackConfiguration
    private var password: String?

    public var isAuthenticated: Bool { password != nil }

    public init(id: UUID = UUID(), serverName: String, serverBaseURL: URL, username: String, password: String? = nil) throws {
        guard let configuration = SMBPlaybackConfiguration(url: serverBaseURL, username: username, password: password) else {
            throw MediaServerError.invalidURL
        }
        self.serverId = id
        self.serverName = serverName
        self.serverBaseURL = serverBaseURL
        self.configuration = configuration
        self.password = password
        if password != nil { SMBPlaybackRegistry.shared.register(configuration, for: id) }
    }

    public func authenticate(username: String, password: String) async throws -> String {
        let configuration = SMBPlaybackConfiguration(url: serverBaseURL, username: username, password: password)
        guard let configuration else { throw MediaServerError.invalidURL }
        try await withClient(configuration: configuration) { client in
            _ = try await client.listDirectory(path: configuration.rootPath)
        }
        self.password = password
        SMBPlaybackRegistry.shared.register(configuration, for: serverId)
        return password
    }

    public func fetchLibraries() async throws -> [MediaLibrary] {
        guard let configuration = authenticatedConfiguration else { throw MediaServerError.notAuthenticated }
        return [MediaLibrary(id: configuration.rootPath, name: configuration.share, collectionType: "videos")]
    }

    public func fetchItems(libraryId: String, startIndex: Int, limit: Int) async throws -> [MediaItem] {
        guard let configuration = authenticatedConfiguration else { throw MediaServerError.notAuthenticated }
        let files = try await scanVideoFiles(configuration: configuration, maximumCount: max(startIndex + limit, 100))
        return Array(files.dropFirst(startIndex).prefix(limit))
    }

    public func fetchPlaybackInfo(itemId: String) async throws -> MediaPlaybackInfo {
        guard let configuration = authenticatedConfiguration else { throw MediaServerError.notAuthenticated }
        guard let url = SMBPlaybackRegistry.shared.url(for: serverId, remotePath: itemId, fileName: URL(fileURLWithPath: itemId).lastPathComponent) else {
            throw MediaServerError.invalidURL
        }
        SMBPlaybackRegistry.shared.register(configuration, for: serverId)
        return MediaPlaybackInfo(itemId: itemId, url: url, method: .directPlay)
    }

    public func fetchPlaybackStreamURL(itemId: String) async throws -> URL {
        try await fetchPlaybackInfo(itemId: itemId).url
    }

    public func search(query: String, limit: Int) async throws -> [MediaItem] {
        guard let configuration = authenticatedConfiguration else { throw MediaServerError.notAuthenticated }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        return try await scanVideoFiles(configuration: configuration, maximumCount: 400)
            .filter { $0.title.localizedCaseInsensitiveContains(needle) }
            .prefix(limit)
            .map { $0 }
    }

    public func fetchContinueWatching(limit: Int) async throws -> [MediaItem] { [] }

    public func reportPlaybackProgress(itemId: String, position: TimeInterval, isPaused: Bool, isStopped: Bool, playSessionId: String?, mediaSourceId: String?) async throws {
        // SMB has no standard playback-history protocol.
    }

    private var authenticatedConfiguration: SMBPlaybackConfiguration? {
        guard let password else { return nil }
        return configuration.with(password: password)
    }

    private func scanVideoFiles(configuration: SMBPlaybackConfiguration, maximumCount: Int) async throws -> [MediaItem] {
        try await withClient(configuration: configuration) { client in
            var pending = [configuration.rootPath]
            var visited = Set<String>()
            var results: [MediaItem] = []
            while let directory = pending.popLast(), results.count < maximumCount, visited.count < 256 {
                guard visited.insert(directory).inserted else { continue }
                for entry in try await client.listDirectory(path: directory) where entry.name != "." && entry.name != ".." {
                    let path = Self.join(directory, entry.name)
                    if entry.isDirectory {
                        pending.append(path)
                    } else if Self.playableExtensions.contains(URL(fileURLWithPath: entry.name).pathExtension.lowercased()) {
                        guard let url = SMBPlaybackRegistry.shared.url(for: serverId, remotePath: path, fileName: entry.name) else { continue }
                        results.append(MediaItem(
                            title: entry.name,
                            url: url,
                            sourceType: .personalMedia,
                            originator: serverName,
                            serverID: serverId,
                            serverItemID: path,
                            containerHint: URL(fileURLWithPath: entry.name).pathExtension.lowercased()
                        ))
                        if results.count == maximumCount { break }
                    }
                }
            }
            return results.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }

    private func withClient<T>(configuration: SMBPlaybackConfiguration, operation: (SMBClient) async throws -> T) async throws -> T {
        let client = SMBClient(host: configuration.host, port: configuration.port)
        do {
            try await client.login(username: configuration.username, password: configuration.password)
            try await client.connectShare(configuration.share)
            let result = try await operation(client)
            _ = try? await client.disconnectShare()
            _ = try? await client.logoff()
            return result
        } catch {
            _ = try? await client.disconnectShare()
            _ = try? await client.logoff()
            throw error
        }
    }

    private static func join(_ directory: String, _ name: String) -> String {
        directory.isEmpty ? name : "\(directory)/\(name)"
    }

    private static let playableExtensions: Set<String> = ["m3u8", "mp4", "m4v", "mov", "mkv", "webm", "avi", "ts", "m2ts", "mpg", "mpeg", "mpd"]
}

public struct SMBPlaybackConfiguration: Sendable {
    public let host: String
    public let port: Int
    public let share: String
    public let rootPath: String
    public let username: String
    public let password: String?

    init?(url: URL, username: String, password: String?) {
        guard url.scheme?.lowercased() == "smb", let host = url.host else { return nil }
        let components = url.pathComponents.filter { $0 != "/" }
        guard let share = components.first, !share.isEmpty else { return nil }
        self.host = host
        self.port = url.port ?? 445
        self.share = share
        self.rootPath = components.dropFirst().joined(separator: "/")
        self.username = username
        self.password = password
    }

    func with(password: String) -> SMBPlaybackConfiguration {
        SMBPlaybackConfiguration(host: host, port: port, share: share, rootPath: rootPath, username: username, password: password)
    }

    private init(host: String, port: Int, share: String, rootPath: String, username: String, password: String?) {
        self.host = host; self.port = port; self.share = share; self.rootPath = rootPath; self.username = username; self.password = password
    }
}

/// Maps opaque AVAsset URLs to their SMB credentials without putting them in
/// URLs, history, diagnostics, or Now Playing metadata.
public final class SMBPlaybackRegistry: @unchecked Sendable {
    public static let shared = SMBPlaybackRegistry()
    private let lock = NSLock()
    private var configurations: [UUID: SMBPlaybackConfiguration] = [:]

    private init() {}

    public func register(_ configuration: SMBPlaybackConfiguration, for serverID: UUID) {
        lock.lock(); defer { lock.unlock() }
        configurations[serverID] = configuration
    }

    public func configuration(for url: URL) -> SMBPlaybackConfiguration? {
        guard url.scheme == "mivu-smb", let host = url.host, let id = UUID(uuidString: host) else { return nil }
        lock.lock(); defer { lock.unlock() }
        return configurations[id]
    }

    public func remotePath(for url: URL) -> String? {
        guard url.scheme == "mivu-smb" else { return nil }
        return url.path.removingPercentEncoding?.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    public func url(for serverID: UUID, remotePath: String, fileName: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mivu-smb"
        components.host = serverID.uuidString
        components.path = "/\(remotePath)"
        return components.url
    }
}
