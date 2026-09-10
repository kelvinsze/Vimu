import Foundation

/// Defines the origin or type of a playable media stream in Mivu.
public enum MediaSourceType: String, Codable, Sendable {
    case directUrl = "direct_url"
    case dlna = "dlna"
    case personalMedia = "personal_media"
    case testStream = "test_stream"
}

/// A server-provided stream that can be tried if the current stream fails.
public struct PlaybackAlternative: Codable, Equatable, Sendable {
    public let url: URL
    public let containerHint: String?
    public let videoCodecHint: String?
    public let playSessionID: String?
    public let mediaSourceID: String?

    public init(url: URL, containerHint: String? = nil, videoCodecHint: String? = nil, playSessionID: String? = nil, mediaSourceID: String? = nil) {
        self.url = url
        self.containerHint = containerHint
        self.videoCodecHint = videoCodecHint
        self.playSessionID = playSessionID
        self.mediaSourceID = mediaSourceID
    }
}

public enum SubtitleFormat: String, Codable, Sendable {
    case srt, vtt, ass, ssa, pgs, vobsub, unknown
}

public struct SubtitleTrack: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let language: String?
    public let title: String?
    public let format: SubtitleFormat
    public let isDefault: Bool
    public let isForced: Bool
    public let isEmbedded: Bool
    public let url: URL?

    public init(id: String, language: String? = nil, title: String? = nil, format: SubtitleFormat = .unknown,
                isDefault: Bool = false, isForced: Bool = false, isEmbedded: Bool = true, url: URL? = nil) {
        self.id = id; self.language = language; self.title = title; self.format = format
        self.isDefault = isDefault; self.isForced = isForced; self.isEmbedded = isEmbedded; self.url = url
    }
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
    public var serverID: UUID?
    public var serverItemID: String?
    public var playSessionID: String?
    public var mediaSourceID: String?
    public var resumePosition: TimeInterval?
    public var containerHint: String?
    public var videoCodecHint: String?
    public var playbackAlternatives: [PlaybackAlternative]?
    public var subtitleTracks: [SubtitleTrack]?
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
        serverID: UUID? = nil,
        serverItemID: String? = nil,
        playSessionID: String? = nil,
        mediaSourceID: String? = nil,
        resumePosition: TimeInterval? = nil,
        containerHint: String? = nil,
        videoCodecHint: String? = nil,
        playbackAlternatives: [PlaybackAlternative] = [],
        subtitleTracks: [SubtitleTrack]? = nil,
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
        self.serverID = serverID
        self.serverItemID = serverItemID
        self.playSessionID = playSessionID
        self.mediaSourceID = mediaSourceID
        self.resumePosition = resumePosition
        self.containerHint = containerHint
        self.videoCodecHint = videoCodecHint
        self.playbackAlternatives = playbackAlternatives
        self.subtitleTracks = subtitleTracks
        self.createdAt = createdAt
    }

    public func withoutSensitiveHeaders() -> MediaItem {
        var copy = self
        copy.headers = nil
        copy.playSessionID = nil
        copy.mediaSourceID = nil
        copy.playbackAlternatives = nil
        return copy
    }

    @discardableResult
    public mutating func advanceToNextPlaybackAlternative() -> Bool {
        guard var alternatives = playbackAlternatives, !alternatives.isEmpty else { return false }
        let next = alternatives.removeFirst()
        playbackAlternatives = alternatives
        url = next.url
        containerHint = next.containerHint
        videoCodecHint = next.videoCodecHint
        playSessionID = next.playSessionID
        mediaSourceID = next.mediaSourceID
        return true
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
            title: "MDN Flower WebM 测试片段 (MPV 验证)",
            url: URL(string: "https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.webm")!,
            sourceType: .testStream,
            mimeType: "video/webm",
            containerHint: "webm"
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
