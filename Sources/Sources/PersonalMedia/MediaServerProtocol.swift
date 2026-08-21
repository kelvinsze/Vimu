import Foundation

/// Unified abstraction protocol for Emby / Jellyfin media servers.
public protocol MediaServerProtocol: Sendable {
    var serverName: String { get }
    var serverBaseURL: URL { get }
    var isAuthenticated: Bool { get }
    var playbackRequestHeaders: [String: String]? { get }

    func authenticate(username: String, password: String) async throws -> String
    func fetchLibraries() async throws -> [MediaLibrary]
    func fetchItems(libraryId: String, startIndex: Int, limit: Int) async throws -> [MediaItem]
    func fetchPlaybackInfo(itemId: String) async throws -> MediaPlaybackInfo
    func search(query: String, limit: Int) async throws -> [MediaItem]
    func fetchContinueWatching(limit: Int) async throws -> [MediaItem]
    func fetchPlaybackStreamURL(itemId: String) async throws -> URL
    func reportPlaybackProgress(itemId: String, position: TimeInterval, isPaused: Bool, isStopped: Bool, playSessionId: String?, mediaSourceId: String?) async throws

    func resolvePlaybackItem(_ item: MediaItem) async throws -> MediaItem
}

public extension MediaServerProtocol {
    var playbackRequestHeaders: [String: String]? { nil }

    func resolvePlaybackItem(_ item: MediaItem) async throws -> MediaItem {
        guard let itemId = item.serverItemID else { return item }
        let playback = try await fetchPlaybackInfo(itemId: itemId)
        var resolved = item
        resolved.url = playback.url
        if let headers = playbackRequestHeaders {
            resolved.headers = headers
        }
        if let resumePosition = playback.resumePosition {
            resolved.resumePosition = resumePosition
        }
        resolved.playSessionID = playback.playSessionId
        resolved.mediaSourceID = playback.mediaSourceId
        return resolved
    }
}

public enum MediaPlaybackMethod: String, Sendable {
    case directPlay
    case directStream
    case transcode
}

public struct MediaPlaybackInfo: Sendable, Equatable {
    public let itemId: String
    public let url: URL
    public let method: MediaPlaybackMethod
    public let playSessionId: String?
    public let mediaSourceId: String?
    public let resumePosition: TimeInterval?

    public init(itemId: String, url: URL, method: MediaPlaybackMethod, playSessionId: String? = nil, mediaSourceId: String? = nil, resumePosition: TimeInterval? = nil) {
        self.itemId = itemId
        self.url = url
        self.method = method
        self.playSessionId = playSessionId
        self.mediaSourceId = mediaSourceId
        self.resumePosition = resumePosition
    }
}

/// Chooses the server-provided URL in Direct Play -> Direct Stream -> Transcode order.
public enum MediaPlaybackInfoSelector {
    public static func select(itemId: String, baseURL: URL, payload: [String: Any], streamPath: String? = nil) -> MediaPlaybackInfo? {
        guard let sources = payload["MediaSources"] as? [[String: Any]] else { return nil }
        for source in sources {
            let mediaSourceId = source["Id"] as? String
            if (source["SupportsDirectPlay"] as? Bool) == true {
                var components = URLComponents(url: baseURL.appendingPathComponent(streamPath ?? "Videos/\(itemId)/stream"), resolvingAgainstBaseURL: false)
                components?.queryItems = [
                    URLQueryItem(name: "Static", value: "true"),
                    URLQueryItem(name: "MediaSourceId", value: mediaSourceId)
                ].filter { $0.value != nil }
                if let url = components?.url {
                    let ticks = (payload["UserData"] as? [String: Any])?["PlaybackPositionTicks"] as? Double
                    let session = payload["PlaySessionId"] as? String ?? source["PlaySessionId"] as? String
                    return MediaPlaybackInfo(itemId: itemId, url: url, method: .directPlay, playSessionId: session, mediaSourceId: mediaSourceId, resumePosition: ticks.map { $0 / 10_000_000 })
                }
            }
            let ordered: [(String, MediaPlaybackMethod, Bool)] = [
                ("DirectStreamUrl", .directStream, (source["SupportsDirectStream"] as? Bool) == true),
                ("TranscodingUrl", .transcode, (source["SupportsTranscoding"] as? Bool) == true)
            ]
            for (key, method, supported) in ordered {
                guard supported, let raw = source[key] as? String, !raw.isEmpty else { continue }
                let url = URL(string: raw, relativeTo: baseURL)?.absoluteURL ?? URL(string: raw)
                guard let url else { continue }
                let ticks = (payload["UserData"] as? [String: Any])?["PlaybackPositionTicks"] as? Double
                let session = payload["PlaySessionId"] as? String ?? source["PlaySessionId"] as? String
                return MediaPlaybackInfo(itemId: itemId, url: url, method: method, playSessionId: session, mediaSourceId: mediaSourceId, resumePosition: ticks.map { $0 / 10_000_000 })
            }
        }
        return nil
    }
}

public struct MediaLibrary: Identifiable, Codable, Sendable {
    public let id: String
    public let name: String
    public let collectionType: String?

    public init(id: String, name: String, collectionType: String? = nil) {
        self.id = id
        self.name = name
        self.collectionType = collectionType
    }
}
