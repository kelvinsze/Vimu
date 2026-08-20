import Foundation

/// Unified abstraction protocol for Emby / Jellyfin media servers.
public protocol MediaServerProtocol: Sendable {
    var serverName: String { get }
    var serverBaseURL: URL { get }
    var isAuthenticated: Bool { get }

    func authenticate(username: String, password: String) async throws -> String
    func fetchLibraries() async throws -> [MediaLibrary]
    func fetchItems(libraryId: String, startIndex: Int, limit: Int) async throws -> [MediaItem]
    func fetchPlaybackStreamURL(itemId: String) async throws -> URL
    func reportPlaybackProgress(itemId: String, position: TimeInterval, isPaused: Bool) async throws
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
