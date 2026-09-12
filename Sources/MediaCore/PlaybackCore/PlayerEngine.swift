import Foundation

/// The small seam between playback policy and a concrete media implementation.
///
/// The interface deliberately contains no AVFoundation, libmpv, or FFmpeg types.
/// Implementations are main-actor isolated because commands and snapshots are
/// consumed by `PlayerService`, which is also main-actor isolated.
@MainActor
public protocol PlayerEngine: AnyObject {
    var snapshot: PlaybackEngineSnapshot { get }
    var events: AsyncStream<PlaybackEngineEvent> { get }
    var renderSurfaceKind: PlaybackRenderSurfaceKind { get }

    func load(_ request: PlaybackRequest)
    func play()
    func pause()
    func stop()
    func seek(to time: TimeInterval)
    func setPlaybackRate(_ rate: Float)
    func setVolume(_ volume: Float)
    func setMuted(_ isMuted: Bool)
    func setSubtitleTrack(_ track: SubtitleTrack?)
}

public enum PlaybackRenderSurfaceKind: String, Equatable, Sendable {
    case nativeAVPlayer
    case mpvSampleBuffer
    case mpvOpenGLES
}

/// A renderer-independent snapshot produced by an engine.
public struct PlaybackEngineSnapshot: Equatable, Sendable {
    public var status: PlaybackStatus
    public var currentTime: TimeInterval
    public var duration: TimeInterval
    public var bufferedTime: TimeInterval
    public var playbackRate: Float
    public var isMuted: Bool
    public var volume: Float
    public var errorMessage: String?

    public init(
        status: PlaybackStatus = .idle,
        currentTime: TimeInterval = 0,
        duration: TimeInterval = 0,
        bufferedTime: TimeInterval = 0,
        playbackRate: Float = 1.0,
        isMuted: Bool = false,
        volume: Float = 1.0,
        errorMessage: String? = nil
    ) {
        self.status = status
        self.currentTime = currentTime
        self.duration = duration
        self.bufferedTime = bufferedTime
        self.playbackRate = playbackRate
        self.isMuted = isMuted
        self.volume = volume
        self.errorMessage = errorMessage
    }
}

public enum PlaybackEngineDiagnostic: Equatable, Sendable {
    case itemStatus(rawValue: Int, duration: TimeInterval, errorMessage: String?)
    case timeControl(rawValue: Int, waitingReason: String?)
    case timeJump
    case streamError(domain: String, code: Int)
    case seekCompleted(target: TimeInterval, finished: Bool)
    case failedToPlayToEnd(message: String, domain: String, code: Int)
    case renderFailure(message: String)
    case presentationSize(width: Double, height: Double)
}

public enum PlaybackEngineEvent: Equatable, Sendable {
    case snapshot(PlaybackEngineSnapshot)
    case ended
    case diagnostic(PlaybackEngineDiagnostic)
}

/// The engine input is intentionally narrower than `MediaItem` and contains no
/// server-specific concepts. `MediaItem` remains the application model.
public struct PlaybackRequest: Equatable, Sendable {
    public let url: URL
    public let headers: [String: String]
    public let startPosition: TimeInterval
    /// An explicit container hint. It is intentionally optional so generic
    /// server `/stream` URLs remain on the Native route.
    public let containerHint: String?
    public let videoCodecHint: String?
    public let subtitleTracks: [SubtitleTrack]

    public init(
        url: URL,
        headers: [String: String] = [:],
        startPosition: TimeInterval = 0,
        containerHint: String? = nil,
        videoCodecHint: String? = nil,
        subtitleTracks: [SubtitleTrack] = []
    ) {
        self.url = url
        self.headers = headers
        self.startPosition = max(0, startPosition)
        self.containerHint = containerHint?.lowercased()
        self.videoCodecHint = videoCodecHint?.lowercased()
        self.subtitleTracks = subtitleTracks
    }
}

public extension MediaItem {
    var playbackRequest: PlaybackRequest {
        PlaybackRequest(
            url: url,
            headers: headers ?? [:],
            startPosition: resumePosition ?? 0,
            containerHint: containerHint ?? mediaItemContainerHint,
            videoCodecHint: videoCodecHint,
            subtitleTracks: subtitleTracks ?? []
        )
    }

    private var mediaItemContainerHint: String? {
        let mime = mimeType?.lowercased()
        switch mime {
        case "video/x-matroska", "video/matroska": return "mkv"
        case "video/x-msvideo": return "avi"
        case "video/x-flv": return "flv"
        case "video/webm": return "webm"
        case "video/mp2t": return "ts"
        default: break
        }

        let extensionName = url.pathExtension.lowercased()
        return ["mkv", "webm", "avi", "flv", "ts", "m2ts", "ogv"].contains(extensionName)
            ? extensionName
            : nil
    }
}
