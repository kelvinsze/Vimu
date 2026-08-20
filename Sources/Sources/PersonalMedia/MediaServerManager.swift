import Foundation
import OSLog

private let logger = Logger(subsystem: "com.kelvinsze.vimu", category: "MediaServerManager")

public struct SavedServerInfo: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var url: URL
    public var serverType: String // "jellyfin" or "emby"
    public var username: String
    public var token: String?
    public var userId: String?

    public init(
        id: UUID = UUID(),
        name: String,
        url: URL,
        serverType: String,
        username: String,
        token: String? = nil,
        userId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.serverType = serverType
        self.username = username
        self.token = token
        self.userId = userId
    }
}

/// Manages personal media server instances (Emby / Jellyfin).
@MainActor
public final class MediaServerManager: ObservableObject {
    public static let shared = MediaServerManager()

    private let storageKey = "vimu_saved_media_servers_v1"
    @Published public private(set) var savedServers: [SavedServerInfo] = []
    @Published public private(set) var activeClients: [UUID: MediaServerProtocol] = [:]

    public init() {
        loadServers()
    }

    public func addServer(name: String, url: URL, type: String, username: String, token: String?, userId: String?) {
        var newInfo = SavedServerInfo(name: name, url: url, serverType: type, username: username, token: token, userId: userId)
        savedServers.append(newInfo)
        saveServers()
        instantiateClient(for: newInfo)
    }

    public func removeServer(id: UUID) {
        savedServers.removeAll { $0.id == id }
        activeClients.removeValue(forKey: id)
        saveServers()
    }

    public func getClient(for id: UUID) -> MediaServerProtocol? {
        return activeClients[id]
    }

    private func loadServers() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            savedServers = try JSONDecoder().decode([SavedServerInfo].self, from: data)
            for server in savedServers {
                instantiateClient(for: server)
            }
        } catch {
            logger.error("Failed to load saved media servers: \(error.localizedDescription)")
        }
    }

    private func saveServers() {
        do {
            let data = try JSONEncoder().encode(savedServers)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            logger.error("Failed to save media servers: \(error.localizedDescription)")
        }
    }

    private func instantiateClient(for info: SavedServerInfo) {
        if info.serverType == "emby" {
            let client = EmbyClient(
                id: info.id,
                serverName: info.name,
                serverBaseURL: info.url,
                accessToken: info.token,
                userId: info.userId
            )
            activeClients[info.id] = client
        } else {
            let client = JellyfinClient(
                id: info.id,
                serverName: info.name,
                serverBaseURL: info.url,
                accessToken: info.token,
                userId: info.userId
            )
            activeClients[info.id] = client
        }
    }
}
