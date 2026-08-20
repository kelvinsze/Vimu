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
    /// Universally accessible test streams (domestic fast CDN + Apple Akamai CDN)
    public static let sampleStreams: [MediaItem] = [
        MediaItem(
            title: "Apple 官方 16:9 HLS 测试流 (高清晰·自适应)",
            url: URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9/bipbop_16x9_variant.m3u8")!,
            sourceType: .testStream,
            mimeType: "application/x-mpegURL"
        ),
        MediaItem(
            title: "高清 MP4 测试短片 1 (国内高速 CDN 直链)",
            url: URL(string: "https://v-cdn.zjol.com.cn/280443.mp4")!,
            sourceType: .testStream,
            mimeType: "video/mp4"
        ),
        MediaItem(
            title: "高清 MP4 测试短片 2 (国内高速 CDN 直链)",
            url: URL(string: "https://v-cdn.zjol.com.cn/276982.mp4")!,
            sourceType: .testStream,
            mimeType: "video/mp4"
        ),
        MediaItem(
            title: "大雄兔 Big Buck Bunny (W3C 标准 MP4 直链)",
            url: URL(string: "https://www.w3schools.com/html/mov_bbb.mp4")!,
            sourceType: .testStream,
            mimeType: "video/mp4"
        ),
        MediaItem(
            title: "Sintel 动画电影预告片 (W3C 标准 MP4 直链)",
            url: URL(string: "https://media.w3.org/2010/05/sintel/trailer.mp4")!,
            sourceType: .testStream,
            mimeType: "video/mp4"
        )
    ]
}
