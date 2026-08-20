import Foundation

/// Defines the origin or type of a playable media stream in Vimu.
public enum MediaSourceType: String, Codable, Sendable {
    case directUrl = "direct_url"
    case dlna = "dlna"
    case personalMedia = "personal_media"
    case testStream = "test_stream"
}

/// Represents a single playable media item.
public struct MediaItem: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var url: URL
    public var sourceType: MediaSourceType
    public var mimeType: String?
    public var duration: TimeInterval?
    public var posterUrl: URL?
    public var headers: [String: String]?
    public var originator: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        url: URL,
        sourceType: MediaSourceType = .directUrl,
        mimeType: String? = nil,
        duration: TimeInterval? = nil,
        posterUrl: URL? = nil,
        headers: [String: String]? = nil,
        originator: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.sourceType = sourceType
        self.mimeType = mimeType
        self.duration = duration
        self.posterUrl = posterUrl
        self.headers = headers
        self.originator = originator
        self.createdAt = createdAt
    }
}

extension MediaItem {
    /// Sample test streams for testing AVPlayer & CarPlay playback in Phase 1
    public static let sampleStreams: [MediaItem] = [
        MediaItem(
            title: "Apple HLS Test (BipBop 4x3)",
            url: URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/bipbop_4x3_variant.m3u8")!,
            sourceType: .testStream,
            mimeType: "application/x-mpegURL"
        ),
        MediaItem(
            title: "Apple HLS Test (BipBop 16x9)",
            url: URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9/bipbop_16x9_variant.m3u8")!,
            sourceType: .testStream,
            mimeType: "application/x-mpegURL"
        ),
        MediaItem(
            title: "Big Buck Bunny (MP4 1080p)",
            url: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4")!,
            sourceType: .testStream,
            mimeType: "video/mp4"
        ),
        MediaItem(
            title: "Tears of Steel (MP4 1080p)",
            url: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4")!,
            sourceType: .testStream,
            mimeType: "video/mp4"
        ),
        MediaItem(
            title: "Elephants Dream (MP4 720p)",
            url: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4")!,
            sourceType: .testStream,
            mimeType: "video/mp4"
        )
    ]
}
