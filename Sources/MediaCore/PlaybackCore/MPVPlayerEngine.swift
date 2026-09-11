import Foundation

@_silgen_name("mivu_mpv_create")
private func mivuMPVCreate() -> UnsafeMutableRawPointer?
@_silgen_name("mivu_mpv_destroy")
private func mivuMPVDestroy(_ player: UnsafeMutableRawPointer?)
@_silgen_name("mivu_mpv_is_initialized")
private func mivuMPVIsInitialized(_ player: UnsafeMutableRawPointer?) -> Int32
@_silgen_name("mivu_mpv_load")
private func mivuMPVLoad(_ player: UnsafeMutableRawPointer?, _ url: UnsafePointer<CChar>, _ headers: UnsafePointer<CChar>?, _ start: Double) -> Int32
@_silgen_name("mivu_mpv_stop")
private func mivuMPVStop(_ player: UnsafeMutableRawPointer?) -> Int32
@_silgen_name("mivu_mpv_set_paused")
private func mivuMPVSetPaused(_ player: UnsafeMutableRawPointer?, _ paused: Int32) -> Int32
@_silgen_name("mivu_mpv_seek")
private func mivuMPVSeek(_ player: UnsafeMutableRawPointer?, _ position: Double) -> Int32
@_silgen_name("mivu_mpv_set_rate")
private func mivuMPVSetRate(_ player: UnsafeMutableRawPointer?, _ rate: Double) -> Int32
@_silgen_name("mivu_mpv_set_volume")
private func mivuMPVSetVolume(_ player: UnsafeMutableRawPointer?, _ volume: Double) -> Int32
@_silgen_name("mivu_mpv_set_muted")
private func mivuMPVSetMuted(_ player: UnsafeMutableRawPointer?, _ muted: Int32) -> Int32
@_silgen_name("mivu_mpv_poll_event")
private func mivuMPVPollEvent(_ player: UnsafeMutableRawPointer?, _ endReason: UnsafeMutablePointer<Int32>?, _ endError: UnsafeMutablePointer<Int32>?) -> Int32
@_silgen_name("mivu_mpv_snapshot")
private func mivuMPVSnapshot(_ player: UnsafeMutableRawPointer?, _ time: UnsafeMutablePointer<Double>?, _ duration: UnsafeMutablePointer<Double>?, _ paused: UnsafeMutablePointer<Int32>?) -> Int32
@_silgen_name("mivu_mpv_last_error")
private func mivuMPVLastError(_ player: UnsafeMutableRawPointer?) -> UnsafePointer<CChar>?
@_silgen_name("mivu_mpv_attach_render")
private func mivuMPVAttachRender(_ player: UnsafeMutableRawPointer?) -> Int32
@_silgen_name("mivu_mpv_render")
private func mivuMPVRender(_ player: UnsafeMutableRawPointer?, _ framebuffer: Int32, _ width: Int32, _ height: Int32) -> Int32
@_silgen_name("mivu_mpv_set_subtitle_id")
private func mivuMPVSetSubtitleID(_ player: UnsafeMutableRawPointer?, _ id: Int32) -> Int32
@_silgen_name("mivu_mpv_add_subtitle")
private func mivuMPVAddSubtitle(_ player: UnsafeMutableRawPointer?, _ url: UnsafePointer<CChar>) -> Int32

#if canImport(MPV)
import GLKit
import OpenGLES
import UIKit

@MainActor
public final class MPVOpenGLESView: GLKView {
    weak var engine: MPVPlayerEngine?
    private var displayLink: CADisplayLink?
    private var drawCount = 0

    public init(engine: MPVPlayerEngine) {
        let context = EAGLContext(api: .openGLES3) ?? EAGLContext(api: .openGLES2)!
        super.init(frame: .zero, context: context)
        self.engine = engine
        engine.recordSurfaceDiagnostic("surface initialized")
        enableSetNeedsDisplay = false
        drawableColorFormat = .RGBA8888
        displayLink = CADisplayLink(target: DisplayLinkTarget { [weak self] in
            guard let self, self.window != nil, !self.bounds.isEmpty else { return }
            self.display()
        }, selector: #selector(DisplayLinkTarget.tick))
        displayLink?.isPaused = false
        displayLink?.add(to: .main, forMode: .common)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { displayLink?.invalidate() }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        displayLink?.isPaused = window == nil
        engine?.recordSurfaceDiagnostic("surface attached=\(window != nil)")
        guard window != nil else { return }
        Task { @MainActor [weak self] in self?.display() }
    }

    public override func draw(_ rect: CGRect) {
        guard EAGLContext.setCurrent(context) else { return }
        drawCount += 1
        engine?.recordSurfaceDiagnostic("surface draw=\(drawCount) size=\(drawableWidth)x\(drawableHeight)")
        var framebuffer: GLint = 0
        glGetIntegerv(GLenum(GL_FRAMEBUFFER_BINDING), &framebuffer)
        _ = engine?.render(framebuffer: Int(framebuffer), width: drawableWidth, height: drawableHeight)
    }

    private final class DisplayLinkTarget: NSObject {
        let onTick: () -> Void
        init(_ onTick: @escaping () -> Void) { self.onTick = onTick }
        @objc func tick() { onTick() }
    }
}

private enum MPVControlEvent {
    case loaded
    case ended(reason: Int32, error: Int32, message: String?)
}

private struct MPVControlUpdate {
    let events: [MPVControlEvent]
    let time: TimeInterval
    let duration: TimeInterval
    let paused: Bool
}

/// The libmpv handle is only used by the serialized control queue. The C API
/// owns the pointed-to storage, so transferring this reference does not
/// transfer mutable Swift-managed state.
private struct MPVControlHandle: @unchecked Sendable {
    let rawValue: UnsafeMutableRawPointer?

    init(_ rawValue: UnsafeMutableRawPointer?) {
        self.rawValue = rawValue
    }
}

@MainActor
public final class MPVPlayerEngine: PlayerEngine {
    public let renderSurfaceKind: PlaybackRenderSurfaceKind = .mpvOpenGLES
    public private(set) var snapshot = PlaybackEngineSnapshot()
    public let events: AsyncStream<PlaybackEngineEvent>
    public private(set) var isOperational = false

    private var eventContinuation: AsyncStream<PlaybackEngineEvent>.Continuation?
    private var eventTask: Task<Void, Never>?
    private var handle: UnsafeMutableRawPointer?
    private let controlQueue = DispatchQueue(label: "app.mivu.mpv.control", qos: .userInitiated)
    private var surfaceView: MPVOpenGLESView?
    private var renderFailureReported = false
    private var renderDiagnosticReported = false
    private var surfaceDiagnostic = "surface not initialized"
    private var pendingSubtitleTrack: SubtitleTrack?
    private var hasLoadedFile = false

    public init() {
        var continuation: AsyncStream<PlaybackEngineEvent>.Continuation?
        events = AsyncStream { continuation = $0 }
        eventContinuation = continuation
        handle = mivuMPVCreate()
        isOperational = mivuMPVIsInitialized(handle) != 0
        eventTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                await self.pollEventsOnControlQueue()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    deinit {
        eventTask?.cancel()
        eventContinuation?.finish()
        if let handle { mivuMPVDestroy(handle) }
    }

    public func makeSurfaceView() -> MPVOpenGLESView? {
        guard isOperational else { return nil }
        if let surfaceView { return surfaceView }
        let view = MPVOpenGLESView(engine: self)
        surfaceView = view
        return view
    }

    /// libmpv requires its render context before a video output is created.
    /// Create it against the reusable GLKView context before `loadfile`.
    @discardableResult
    public func prepareSurfaceForLoading() -> Bool {
        guard let surfaceView = makeSurfaceView() else {
            fail("Unable to prepare the MPV OpenGL ES context")
            return false
        }
        let context = surfaceView.context
        guard EAGLContext.setCurrent(context) else {
            fail("Unable to prepare the MPV OpenGL ES context")
            return false
        }
        let result = mivuMPVAttachRender(handle)
        if result < 0 {
            fail("Unable to create the MPV OpenGL ES renderer")
            return false
        }
        return true
    }

    public func latestRenderDiagnostic() -> String {
        "\(surfaceDiagnostic); \(renderDiagnostic())"
    }

    fileprivate func recordSurfaceDiagnostic(_ message: String) {
        surfaceDiagnostic = message
    }

    public func load(_ request: PlaybackRequest) {
        guard isOperational else {
            fail("MPV framework is unavailable")
            return
        }
        hasLoadedFile = false
        pendingSubtitleTrack = nil
        renderFailureReported = false
        renderDiagnosticReported = false
        updateSnapshot {
            $0.status = .loading
            $0.currentTime = request.startPosition
            $0.duration = 0
            $0.bufferedTime = 0
            $0.errorMessage = nil
        }
        // Newlines delimit complete header fields without corrupting values such
        // as X-Emby-Authorization, whose value legitimately contains commas.
        let headerString = request.headers
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "\n")
        let sourceURL: URL
        if request.url.scheme?.lowercased() == "mivu-smb" {
            guard let proxyURL = SMBLocalHTTPProxy.shared.url(for: request.url) else {
                fail("SMB local stream is unavailable")
                return
            }
            sourceURL = proxyURL
        } else {
            sourceURL = request.url
        }
        let handle = MPVControlHandle(handle)
        controlQueue.async { [weak self] in
            let result = sourceURL.absoluteString.withCString { url in
                headerString.withCString { headers in
                    mivuMPVLoad(handle.rawValue, url, headerString.isEmpty ? nil : headers, request.startPosition)
                }
            }
            guard result < 0 else { return }
            let message = Self.controlError(handle.rawValue)
            Task { @MainActor [weak self] in self?.fail(message) }
        }
    }

    public func play() {
        guard isOperational else { return }
        let handle = MPVControlHandle(handle)
        controlQueue.async { _ = mivuMPVSetPaused(handle.rawValue, 0) }
        updateSnapshot { $0.status = .playing; $0.errorMessage = nil }
    }

    public func pause() {
        guard isOperational else { return }
        let handle = MPVControlHandle(handle)
        controlQueue.async { _ = mivuMPVSetPaused(handle.rawValue, 1) }
        updateSnapshot { $0.status = .paused }
    }

    public func stop() {
        let handle = MPVControlHandle(handle)
        controlQueue.async { _ = mivuMPVStop(handle.rawValue) }
        hasLoadedFile = false
        pendingSubtitleTrack = nil
        updateSnapshot {
            $0.status = .stopped
            $0.currentTime = 0
            $0.duration = 0
            $0.bufferedTime = 0
            $0.errorMessage = nil
        }
    }

    public func seek(to time: TimeInterval) {
        let target = max(0, time)
        let handle = MPVControlHandle(handle)
        controlQueue.async { [weak self] in
            let result = mivuMPVSeek(handle.rawValue, target)
            Task { @MainActor [weak self] in
                self?.eventContinuation?.yield(.diagnostic(.seekCompleted(target: target, finished: result >= 0)))
            }
        }
    }

    public func setPlaybackRate(_ rate: Float) {
        let clamped = max(0.1, rate)
        let handle = MPVControlHandle(handle)
        controlQueue.async { _ = mivuMPVSetRate(handle.rawValue, Double(clamped)) }
        updateSnapshot { $0.playbackRate = clamped }
    }

    public func setVolume(_ volume: Float) {
        let clamped = max(0, min(volume, 1))
        let handle = MPVControlHandle(handle)
        controlQueue.async { _ = mivuMPVSetVolume(handle.rawValue, Double(clamped)) }
        updateSnapshot { $0.volume = clamped }
    }

    public func setMuted(_ isMuted: Bool) {
        let handle = MPVControlHandle(handle)
        controlQueue.async { _ = mivuMPVSetMuted(handle.rawValue, isMuted ? 1 : 0) }
        updateSnapshot { $0.isMuted = isMuted }
    }

    public func setSubtitleTrack(_ track: SubtitleTrack?) {
        pendingSubtitleTrack = track
        guard hasLoadedFile else {
            SSDPService.shared.recordPlaybackDebug("[DEBUG-subtitle] MPV_DEFER id=\(track?.id ?? "off")")
            return
        }
        applySubtitleTrack(track)
    }

    private func applySubtitleTrack(_ track: SubtitleTrack?) {
        let handle = MPVControlHandle(handle)
        guard let track else {
            controlQueue.async {
                let result = mivuMPVSetSubtitleID(handle.rawValue, 0)
                Task { @MainActor in
                    SSDPService.shared.recordPlaybackDebug("[DEBUG-subtitle] MPV_SID id=0 result=\(result)")
                }
            }
            return
        }
        if !track.isEmbedded, let url = track.url {
            controlQueue.async {
                let result = url.absoluteString.withCString { mivuMPVAddSubtitle(handle.rawValue, $0) }
                Task { @MainActor in
                    SSDPService.shared.recordPlaybackDebug("[DEBUG-subtitle] MPV_SUB_ADD id=\(track.id) result=\(result)")
                }
            }
        } else if let id = Int32(track.id) {
            controlQueue.async {
                let result = mivuMPVSetSubtitleID(handle.rawValue, id)
                Task { @MainActor in
                    SSDPService.shared.recordPlaybackDebug("[DEBUG-subtitle] MPV_SID id=\(id) result=\(result)")
                }
            }
        }
    }

    fileprivate func render(framebuffer: Int, width: Int, height: Int) -> Int32 {
        guard let handle, width > 0, height > 0 else { return -1 }
        if mivuMPVAttachRender(handle) < 0 {
            reportRenderFailure()
            return -1
        }
        let result = mivuMPVRender(handle, Int32(framebuffer), Int32(width), Int32(height))
        if !renderDiagnosticReported {
            renderDiagnosticReported = true
            SSDPService.shared.recordPlaybackDebug("MPV_RENDER \(renderDiagnostic())")
        }
        if result < 0 { reportRenderFailure() }
        return result
    }

    private func pollEventsOnControlQueue() async {
        guard isOperational else { return }
        let handle = MPVControlHandle(handle)
        let update = await withCheckedContinuation { continuation in
            controlQueue.async {
                continuation.resume(returning: Self.collectControlUpdate(handle.rawValue))
            }
        }
        applyControlUpdate(update)
    }

    nonisolated private static func collectControlUpdate(_ handle: UnsafeMutableRawPointer?) -> MPVControlUpdate {
        var events: [MPVControlEvent] = []
        var endReason: Int32 = 0
        var endError: Int32 = 0
        var event = mivuMPVPollEvent(handle, &endReason, &endError)
        while event > 0 {
            if event == 1 {
                events.append(.loaded)
            } else if event == 2 {
                let message = endError < 0 ? controlError(handle) : nil
                events.append(.ended(reason: endReason, error: endError, message: message))
            }
            event = mivuMPVPollEvent(handle, &endReason, &endError)
        }
        var time = 0.0
        var duration = 0.0
        var paused: Int32 = 1
        guard mivuMPVSnapshot(handle, &time, &duration, &paused) >= 0 else {
            return MPVControlUpdate(events: events, time: 0, duration: 0, paused: true)
        }
        return MPVControlUpdate(events: events, time: time, duration: duration, paused: paused != 0)
    }

    private func applyControlUpdate(_ update: MPVControlUpdate) {
        for event in update.events {
            switch event {
            case .loaded:
                hasLoadedFile = true
                applySubtitleTrack(pendingSubtitleTrack)
                updateSnapshot {
                    $0.status = .playing
                    $0.errorMessage = nil
                }
                eventContinuation?.yield(.diagnostic(.itemStatus(rawValue: 1, duration: snapshot.duration, errorMessage: nil)))
            case let .ended(reason, error, message):
                if reason == 4 || error < 0 {
                    let errorMessage = message ?? "MPV playback ended with an error"
                    SSDPService.shared.recordPlaybackDebug("MPV_END_FILE reason=\(reason) error=\(error) message=\(errorMessage)")
                    fail(errorMessage)
                } else if !hasLoadedFile {
                    SSDPService.shared.recordPlaybackDebug("MPV_END_FILE ignored_before_load reason=\(reason) error=\(error)")
                } else {
                    updateSnapshot { $0.status = .stopped }
                    eventContinuation?.yield(.ended)
                }
            }
        }
        updateSnapshot {
            $0.currentTime = update.time
            $0.duration = update.duration
            if $0.status != .loading && $0.status != .stopped && $0.status != .failed {
                $0.status = update.paused ? .paused : .playing
            }
        }
    }

    private func updateSnapshot(_ update: (inout PlaybackEngineSnapshot) -> Void) {
        var next = snapshot
        update(&next)
        snapshot = next
        eventContinuation?.yield(.snapshot(next))
    }

    private func fail(_ message: String) {
        updateSnapshot {
            $0.status = .failed
            $0.errorMessage = message
        }
        eventContinuation?.yield(.diagnostic(.itemStatus(rawValue: 2, duration: snapshot.duration, errorMessage: message)))
    }

    private func reportRenderFailure() {
        guard !renderFailureReported else { return }
        renderFailureReported = true
        let message = renderDiagnostic()
        updateSnapshot {
            $0.status = .failed
            $0.errorMessage = message
        }
        eventContinuation?.yield(.diagnostic(.renderFailure(message: message)))
    }

    nonisolated private static func controlError(_ handle: UnsafeMutableRawPointer?) -> String {
        guard let pointer = mivuMPVLastError(handle) else { return "MPV playback failed" }
        return String(cString: pointer)
    }

    private func renderDiagnostic() -> String {
        guard let pointer = mivuMPVLastError(handle) else { return "MPV OpenGL ES rendering failed" }
        return String(cString: pointer)
    }
}
#else

@MainActor
public final class MPVPlayerEngine: PlayerEngine {
    public let renderSurfaceKind: PlaybackRenderSurfaceKind = .nativeAVPlayer
    public private(set) var snapshot = PlaybackEngineSnapshot()
    public let events: AsyncStream<PlaybackEngineEvent>
    public let isOperational = false

    public init() {
        events = AsyncStream { continuation in continuation.finish() }
    }

    public func load(_ request: PlaybackRequest) {}
    public func latestRenderDiagnostic() -> String { "MPV framework is unavailable" }
    public func play() {}
    public func pause() {}
    public func stop() {}
    public func seek(to time: TimeInterval) {}
    public func setPlaybackRate(_ rate: Float) {}
    public func setVolume(_ volume: Float) {}
    public func setMuted(_ isMuted: Bool) {}
    public func setSubtitleTrack(_ track: SubtitleTrack?) {}
    @discardableResult public func prepareSurfaceForLoading() -> Bool { false }
}
#endif
