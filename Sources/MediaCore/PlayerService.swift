import Foundation
import AVFoundation
import MediaPlayer
import OSLog
import Combine

private let logger = Logger(subsystem: "com.kelvinsze.mivu", category: "PlayerService")

/// Core video playback service for Mivu, managing AVPlayer, audio session,
/// Now Playing info, and remote control events.
@MainActor
public final class PlayerService: ObservableObject {
    public static let shared = PlayerService()

    @Published public private(set) var session: PlaybackSession = PlaybackSession()
    @Published public private(set) var player: AVPlayer
    @Published public private(set) var renderSurfaceKind: PlaybackRenderSurfaceKind = .nativeAVPlayer
    @Published public var videoGravity: AVLayerVideoGravity = .resizeAspect
    @Published public var selectedSpeed: Float = 1.0
    @Published public private(set) var subtitleTracks: [SubtitleTrack] = []
    @Published public private(set) var selectedSubtitleTrack: SubtitleTrack?

    private let nativeEngine: AVPlayerEngine
    private let mpvEngine: MPVPlayerEngine?
    private var engine: PlayerEngine
    private var engineTask: Task<Void, Never>?
    private var engineGeneration = 0
    private var cancellables = Set<AnyCancellable>()
    private var lastProgressReportDate = Date.distantPast
    private var castTraceGeneration = 0
    private var lastTracePlayerTime: TimeInterval?
    private var lastTraceSnapshotAt: TimeInterval = 0
    private var pendingSeekOrigin: (target: TimeInterval, origin: String)?
    private var mpvFallbackAttempted = false

    public init() {
        let avEngine = AVPlayerEngine()
        let candidateMPV = MPVPlayerEngine()
        self.nativeEngine = avEngine
        self.mpvEngine = candidateMPV.isOperational ? candidateMPV : nil
        self.engine = avEngine
        self.player = avEngine.player

        setupAudioSession()
        setupRemoteCommands()
        setupNotifications()
        observeEngineEvents()
    }

    /// The active MPV adapter is exposed only for the MPV surface view. All
    /// playback commands continue to flow through PlayerService.
    public var activeMPVEngine: MPVPlayerEngine? {
        engine as? MPVPlayerEngine
    }

    public var activeMPVRenderDiagnostic: String? {
        activeMPVEngine?.latestRenderDiagnostic()
    }

    // MARK: - Audio Session

    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            // moviePlayback mode handles AirPlay and Bluetooth routing automatically.
            // Passing explicit options with moviePlayback triggers OSStatus error -50 (kAudio_ParamError).
            try audioSession.setCategory(.playback, mode: .moviePlayback)
            try audioSession.setActive(true)
            logger.info("AVAudioSession configured for background video playback.")
        } catch {
            logger.error("Failed to configure AVAudioSession: \(error.localizedDescription)")
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            try? AVAudioSession.sharedInstance().setActive(true)
        }
    }

    // MARK: - Playback Control

    public func loadAndPlay(item: MediaItem, origin: String = #function, recordHistory: Bool = true) {
        setupAudioSession()
        mpvFallbackAttempted = false
        subtitleTracks = item.subtitleTracks ?? []
        let subtitleKey = subtitlePreferenceKey(for: item)
        let savedSubtitleID = UserDefaults.standard.string(forKey: subtitleKey)
        // An empty value represents an explicit user choice to keep subtitles
        // off; a missing value still follows the server's default track.
        selectedSubtitleTrack = savedSubtitleID == ""
            ? nil
            : subtitleTracks.first { $0.id == savedSubtitleID } ?? subtitleTracks.first(where: \.isDefault)
        // Start through MPV when the initial selection is an external subtitle.
        // This avoids loading Native first, then immediately replacing it and
        // producing a visible playback hitch.
        selectEngine(for: item, forceMPV: selectedSubtitleTrack?.isEmbedded == false)
        if let mpvEngine = engine as? MPVPlayerEngine {
            _ = mpvEngine.prepareSurfaceForLoading()
        }
        if item.sourceType == .dlna {
            castTraceGeneration += 1
            SSDPService.shared.recordCastDebug("LOAD g=\(castTraceGeneration) origin=\(origin) sameURL=\(session.currentItem?.url == item.url) previous=\(traceTime(player.currentTime().seconds)) host=\(item.url.host ?? "local")")
        }
        lastTracePlayerTime = nil
        lastTraceSnapshotAt = 0
        logger.info("Loading media item: \(item.title) (\(item.url.absoluteString))")
        SSDPService.shared.recordPlaybackDebug(
            "LOAD origin=\(origin) source=\(item.sourceType.rawValue) engine=\(engineName) container=\(item.playbackRequest.containerHint ?? "unknown") codec=\(item.playbackRequest.videoCodecHint ?? "unknown") alternatives=\(item.playbackAlternatives?.count ?? 0) url=\(SSDPService.sanitizedPlaybackURL(item.url))"
        )

        // Update session
        session.currentItem = item
        lastProgressReportDate = .distantPast
        session.status = .loading
        let resumePosition = max(0, item.resumePosition ?? 0)
        session.currentTime = resumePosition
        session.duration = item.duration ?? 0
        session.bufferedTime = 0
        session.errorMessage = nil

        // The AVFoundation lifecycle and item observers now live behind the engine seam.
        traceCast("REPLACE_ITEM")
        engine.setPlaybackRate(selectedSpeed)
        engine.load(item.playbackRequest)
        engine.setSubtitleTrack(selectedSubtitleTrack)

        // Record into history
        if recordHistory {
            PlaybackHistory.shared.addOrUpdate(item: item)
        }
        updateNowPlayingInfo()
    }

    public func play() {
        guard session.currentItem != nil else { return }
        traceCast("PLAY")
        engine.setPlaybackRate(selectedSpeed)
        engine.play()
        session.status = .playing
        updateNowPlayingInfo()
    }

    public func pause() {
        traceCast("PAUSE")
        engine.pause()
        session.status = .paused
        updateNowPlayingInfo()
        reportPlaybackProgress(force: true, isPaused: true, isStopped: false)
    }

    public func stop() {
        traceCast("STOP / REMOVE_ITEM")
        reportPlaybackProgress(force: true, isPaused: true, isStopped: true)
        engine.stop()
        session.status = .stopped
        session.currentTime = 0
        session.duration = 0
        session.bufferedTime = 0
        updateNowPlayingInfo()
    }

    public func togglePlayPause() {
        if session.status == .playing {
            pause()
        } else {
            play()
        }
    }

    public func seek(to seconds: TimeInterval, origin: String = #function) {
        let targetSeconds = max(0, min(seconds, session.duration > 0 ? session.duration : seconds))
        traceCast("SEEK origin=\(origin) target=\(traceTime(targetSeconds))")
        pendingSeekOrigin = (targetSeconds, origin)
        engine.seek(to: targetSeconds)
    }

    public func seek(by deltaSeconds: TimeInterval, origin: String = #function) {
        let target = session.currentTime + deltaSeconds
        seek(to: target, origin: origin)
    }

    public func setRate(_ rate: Float) {
        self.selectedSpeed = rate
        session.playbackRate = rate
        engine.setPlaybackRate(rate)
    }

    public func toggleVideoGravity() {
        if videoGravity == .resizeAspect {
            videoGravity = .resizeAspectFill
        } else {
            videoGravity = .resizeAspect
        }
        player.externalPlaybackVideoGravity = videoGravity
    }

    public func setVolume(_ volume: Float) {
        let clamped = max(0.0, min(volume, 1.0))
        engine.setVolume(clamped)
        session.volume = clamped
    }

    public func setMuted(_ isMuted: Bool) {
        engine.setMuted(isMuted)
        session.isMuted = isMuted
    }

    public func setSubtitleTrack(_ track: SubtitleTrack?, persistPreference: Bool = true) {
        let previousID = selectedSubtitleTrack?.id ?? "off"
        let nextID = track?.id ?? "off"
        SSDPService.shared.recordPlaybackDebug(
            "[DEBUG-subtitle] REQUEST engine=\(engineName) from=\(previousID) to=\(nextID) external=\(track?.isEmbedded == false) position=\(traceTime(session.currentTime))"
        )
        if let track,
           !track.isEmbedded,
           engine !== mpvEngine,
           let item = session.currentItem,
           mpvEngine?.isOperational == true {
            // AVPlayer cannot attach a standalone, authenticated subtitle URL.
            // Reopen through MPV so its HTTP headers and libass path apply.
            selectEngine(for: item, forceMPV: true)
            let request = PlaybackRequest(
                url: item.url,
                headers: item.headers ?? [:],
                startPosition: session.currentTime,
                containerHint: item.containerHint,
                videoCodecHint: item.videoCodecHint,
                subtitleTracks: item.subtitleTracks ?? []
            )
            engine.setPlaybackRate(selectedSpeed)
            SSDPService.shared.recordPlaybackDebug("[DEBUG-subtitle] FORCE_MPV_RELOAD position=\(traceTime(session.currentTime))")
            engine.load(request)
        }
        selectedSubtitleTrack = track
        engine.setSubtitleTrack(track)
        SSDPService.shared.recordPlaybackDebug("[DEBUG-subtitle] APPLIED engine=\(engineName) id=\(nextID)")
        if persistPreference, let item = session.currentItem {
            let key = subtitlePreferenceKey(for: item)
            if let track { UserDefaults.standard.set(track.id, forKey: key) }
            else { UserDefaults.standard.set("", forKey: key) }
        }
    }

    private func subtitlePreferenceKey(for item: MediaItem) -> String {
        "mivu.subtitle.\(item.serverID?.uuidString ?? "local").\(item.serverItemID ?? item.id.uuidString)"
    }

    // MARK: - Observers & Handlers

    private func observeEngineEvents() {
        engineTask?.cancel()
        let engine = self.engine
        engineGeneration += 1
        let generation = engineGeneration
        engineTask = Task { @MainActor [weak self] in
            for await event in engine.events {
                guard let self, !Task.isCancelled, self.engineGeneration == generation else { return }
                self.handleEngineEvent(event)
            }
        }
    }

    private func selectEngine(for item: MediaItem, forceMPV: Bool = false) {
        let route: PlaybackRoute = forceMPV && mpvEngine?.isOperational == true
            ? .mpv
            : PlaybackRouter.route(
                for: item.playbackRequest,
                mpvAvailable: mpvEngine?.isOperational == true
            )
        let selected: PlayerEngine
        switch route {
        case .native:
            selected = nativeEngine
        case .mpv:
            guard let mpvEngine else {
                selected = nativeEngine
                break
            }
            selected = mpvEngine
        }

        guard engine !== selected else { return }
        engineGeneration += 1
        engineTask?.cancel()
        engine.stop()
        engine = selected
        renderSurfaceKind = selected.renderSurfaceKind
        observeEngineEvents()
    }

    private func handleEngineEvent(_ event: PlaybackEngineEvent) {
        switch event {
        case .snapshot(let snapshot):
            if session.currentItem?.sourceType == .dlna {
                let current = snapshot.currentTime
                if let previous = lastTracePlayerTime, current < previous - 0.5 {
                    traceCast("TIME_BACKWARD \(traceTime(previous))->\(traceTime(current))")
                }
                lastTracePlayerTime = current
                let now = ProcessInfo.processInfo.systemUptime
                if now - lastTraceSnapshotAt >= 1 {
                    lastTraceSnapshotAt = now
                    traceCast("TICK sampled=\(traceTime(current))")
                }
            }

            let previousStatus = session.status
            let statusChanged = previousStatus != snapshot.status
            var nextSession = session
            nextSession.status = snapshot.status
            nextSession.currentTime = max(0, snapshot.currentTime)
            if snapshot.duration > 0 {
                nextSession.duration = snapshot.duration
            }
            nextSession.bufferedTime = snapshot.bufferedTime
            nextSession.playbackRate = snapshot.playbackRate
            nextSession.isMuted = snapshot.isMuted
            nextSession.volume = snapshot.volume
            nextSession.errorMessage = snapshot.errorMessage
            if nextSession != session {
                session = nextSession
            }
            if snapshot.status == .playing {
                reportPlaybackProgress(force: false, isPaused: false, isStopped: false)
            }
            if statusChanged {
                SSDPService.shared.recordPlaybackDebug(
                    "STATE engine=\(engineName) from=\(previousStatus.rawValue) to=\(snapshot.status.rawValue) position=\(traceTime(snapshot.currentTime)) duration=\(traceTime(snapshot.duration)) error=\(snapshot.errorMessage ?? "none")"
                )
                updateNowPlayingInfo()
            }
            if snapshot.status == .failed {
                handlePlaybackFailure()
            }

        case .ended:
            traceCast("DID_END currentItem=\(player.currentItem != nil)")
            logger.info("Reached end of media playback.")
            session.status = .stopped
            reportPlaybackProgress(force: true, isPaused: true, isStopped: true)
            updateNowPlayingInfo()

        case .diagnostic(let diagnostic):
            switch diagnostic {
            case .itemStatus(let rawValue, let duration, let errorMessage):
                traceCast("ITEM_STATUS=\(rawValue) currentItem=\(player.currentItem != nil) duration=\(traceTime(duration))")
                SSDPService.shared.recordPlaybackDebug("ITEM_STATUS engine=\(engineName) raw=\(rawValue) duration=\(traceTime(duration)) error=\(errorMessage ?? "none")")
                if rawValue == AVPlayerItem.Status.readyToPlay.rawValue {
                    logger.info("Media ready to play. Duration: \(duration)s")
                    if session.currentItem?.sourceType == .dlna {
                        SSDPService.shared.recordPlaybackStage("媒体已就绪", successful: true)
                    }
                } else if rawValue == AVPlayerItem.Status.failed.rawValue {
                    if session.currentItem?.sourceType == .dlna {
                        SSDPService.shared.recordPlaybackStage("媒体加载失败：\(errorMessage ?? "Unknown playback error")")
                    }
                }
            case .timeControl(let rawValue, let waitingReason):
                traceCast("TIME_CONTROL=\(rawValue) waiting=\(waitingReason ?? "none")")
                SSDPService.shared.recordPlaybackDebug("TIME_CONTROL engine=\(engineName) raw=\(rawValue) waiting=\(waitingReason ?? "none")")
            case .timeJump:
                traceCast("TIME_JUMP previousSample=\(traceTime(lastTracePlayerTime ?? .nan))")
            case .streamError(let domain, let code):
                traceCast("STREAM_ERROR domain=\(domain) code=\(code)")
                SSDPService.shared.recordPlaybackDebug("STREAM_ERROR engine=\(engineName) domain=\(domain) code=\(code)")
            case .seekCompleted(let target, let finished):
                if let pending = pendingSeekOrigin, abs(pending.target - target) < 0.01 {
                    traceCast("SEEK_COMPLETED origin=\(pending.origin) target=\(traceTime(target)) finished=\(finished)")
                    if finished {
                        updateNowPlayingInfo()
                    }
                    pendingSeekOrigin = nil
                }
            case .failedToPlayToEnd(let message, let domain, let code):
                traceCast("FAILED_TO_END domain=\(domain) code=\(code)")
                session.status = .failed
                session.errorMessage = message
                logger.error("Player item failed to play to end: \(message)")
            case .renderFailure(let message):
                guard engine is MPVPlayerEngine else { return }
                traceCast("RENDER_FAILURE message=\(message)")
                session.status = .failed
                session.errorMessage = message
                logger.error("MPV render failed: \(message)")
            case .presentationSize(let width, let height):
                SSDPService.shared.recordPlaybackDebug("VIDEO_PRESENTATION engine=\(engineName) width=\(Int(width)) height=\(Int(height))")
            }
        }
    }

    private func handlePlaybackFailure() {
        let hasServerAlternative = session.currentItem?.playbackAlternatives?.isEmpty == false
        if engine is MPVPlayerEngine, !mpvFallbackAttempted, !hasServerAlternative {
            // Skip the AVPlayer fallback for containers that AVPlayer definitely
            // cannot decode (WebM, MKV, etc.). Falling back would just produce a
            // second silent failure and hide the original MPV error from the user.
            let container = session.currentItem?.playbackRequest.containerHint ?? ""
            let nativeUnsupported: Set<String> = ["webm", "mkv", "avi", "flv", "ogv"]
            if nativeUnsupported.contains(container) {
                SSDPService.shared.recordPlaybackDebug("FALLBACK skipped_native_unsupported container=\(container) engine=\(engineName) error=\(session.errorMessage ?? "unknown")")
            } else {
                fallbackToNativeAfterMPVFailure()
            }
            return
        }
        if engine is AVPlayerEngine,
           !mpvFallbackAttempted,
           !hasServerAlternative,
           session.currentItem?.url.scheme?.lowercased() == "mivu-smb",
           mpvEngine?.isOperational == true,
           let item = session.currentItem,
           SMBLocalHTTPProxy.shared.url(for: item.url) != nil {
            fallbackToMPVAfterNativeSMBFailure()
            return
        }

        guard var nextItem = session.currentItem,
              nextItem.advanceToNextPlaybackAlternative() else {
            SSDPService.shared.recordPlaybackDebug("FALLBACK exhausted engine=\(engineName) error=\(session.errorMessage ?? "unknown")")
            return
        }
        logger.error("Playback failed; trying the next server-provided stream.")
        SSDPService.shared.recordPlaybackDebug("FALLBACK next url=\(SSDPService.sanitizedPlaybackURL(nextItem.url)) remaining=\(nextItem.playbackAlternatives?.count ?? 0)")
        loadAndPlay(item: nextItem, origin: "playbackFallback", recordHistory: false)
    }

    private func fallbackToNativeAfterMPVFailure() {
        guard !mpvFallbackAttempted,
              engine is MPVPlayerEngine,
              let item = session.currentItem else { return }
        mpvFallbackAttempted = true
        logger.error("MPV playback failed; retrying the same item with AVPlayer.")
        SSDPService.shared.recordPlaybackDebug("FALLBACK mpv_to_native_same_url url=\(SSDPService.sanitizedPlaybackURL(item.url))")
        let originalRequest = item.playbackRequest
        let fallbackPosition = max(session.currentTime, originalRequest.startPosition)
        let fallbackRequest = PlaybackRequest(
            url: originalRequest.url,
            headers: originalRequest.headers,
            startPosition: fallbackPosition,
            containerHint: originalRequest.containerHint,
            videoCodecHint: originalRequest.videoCodecHint
        )

        engineGeneration += 1
        engineTask?.cancel()
        engine.stop()
        nativeEngine.stop()
        engine = nativeEngine
        renderSurfaceKind = .nativeAVPlayer
        observeEngineEvents()

        session.status = .loading
        session.currentTime = fallbackPosition
        session.duration = item.duration ?? 0
        session.bufferedTime = 0
        session.errorMessage = nil
        engine.setPlaybackRate(selectedSpeed)
        engine.load(fallbackRequest)
        updateNowPlayingInfo()
    }

    private func fallbackToMPVAfterNativeSMBFailure() {
        guard !mpvFallbackAttempted,
              engine is AVPlayerEngine,
              let mpvEngine,
              let item = session.currentItem else { return }
        mpvFallbackAttempted = true
        let request = item.playbackRequest
        let fallbackPosition = max(session.currentTime, request.startPosition)
        logger.error("AVPlayer could not decode SMB media; retrying through MPV loopback stream.")
        SSDPService.shared.recordPlaybackDebug("FALLBACK smb_native_to_mpv position=\(traceTime(fallbackPosition))")

        engineGeneration += 1
        engineTask?.cancel()
        engine.stop()
        mpvEngine.stop()
        engine = mpvEngine
        renderSurfaceKind = .mpvOpenGLES
        observeEngineEvents()

        session.status = .loading
        session.currentTime = fallbackPosition
        session.errorMessage = nil
        engine.setPlaybackRate(selectedSpeed)
        engine.load(PlaybackRequest(
            url: request.url,
            headers: request.headers,
            startPosition: fallbackPosition,
            containerHint: request.containerHint,
            videoCodecHint: request.videoCodecHint,
            subtitleTracks: request.subtitleTracks
        ))
        updateNowPlayingInfo()
    }

    private func setupNotifications() {
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .sink { [weak self] notification in
                Task { @MainActor [weak self] in
                    self?.handleAudioInterruption(notification)
                }
            }
            .store(in: &cancellables)
    }

    private func reportPlaybackProgress(force: Bool, isPaused: Bool, isStopped: Bool) {
        guard let item = session.currentItem,
              let itemId = item.serverItemID,
              let serverID = item.serverID else { return }
        if !force && !isStopped && Date().timeIntervalSince(lastProgressReportDate) < 15 { return }
        lastProgressReportDate = Date()
        guard let client = MediaServerManager.shared.getClient(for: serverID) else { return }
        let position = session.currentTime
        Task {
            do {
                try await client.reportPlaybackProgress(
                    itemId: itemId,
                    position: position,
                    isPaused: isPaused,
                    isStopped: isStopped,
                    playSessionId: item.playSessionID,
                    mediaSourceId: item.mediaSourceID
                )
            } catch {
                logger.debug("Playback progress report failed: \(error.localizedDescription)")
            }
        }
    }

    private func traceTime(_ value: TimeInterval) -> String {
        value.isFinite ? String(format: "%.3f", value) : "unknown"
    }

    private var engineName: String {
        engine is MPVPlayerEngine ? "mpv" : "avplayer"
    }

    private func traceCast(_ event: String) {
        guard session.currentItem?.sourceType == .dlna else { return }
        SSDPService.shared.recordCastDebug("\(event) g=\(castTraceGeneration) player=\(traceTime(player.currentTime().seconds)) reported=\(traceTime(session.currentTime)) duration=\(traceTime(session.duration)) state=\(session.status.rawValue) rate=\(player.rate)")
    }

    private func handleAudioInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            logger.info("Audio interruption began (e.g. phone call). Pausing player.")
            pause()
        case .ended:
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                logger.info("Audio interruption ended. Resuming playback.")
                play()
            }
        @unknown default:
            break
        }
    }

    // MARK: - Now Playing & Remote Control

    private func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.play()
            }
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pause()
            }
            return .success
        }

        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.togglePlayPause()
            }
            return .success
        }

        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [15]
        commandCenter.skipForwardCommand.addTarget { [weak self] event in
            guard let skipEvent = event as? MPSkipIntervalCommandEvent else { return .commandFailed }
            Task { @MainActor [weak self] in
                self?.seek(by: skipEvent.interval, origin: "RemoteCommand.skipForward")
            }
            return .success
        }

        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { [weak self] event in
            guard let skipEvent = event as? MPSkipIntervalCommandEvent else { return .commandFailed }
            Task { @MainActor [weak self] in
                self?.seek(by: -skipEvent.interval, origin: "RemoteCommand.skipBackward")
            }
            return .success
        }

        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor [weak self] in
                self?.seek(to: positionEvent.positionTime, origin: "RemoteCommand.changePlaybackPosition")
            }
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        var info: [String: Any] = [:]
        if let currentItem = session.currentItem {
            info[MPMediaItemPropertyTitle] = currentItem.title
            info[MPMediaItemPropertyArtist] = currentItem.originator ?? "Mivu Receiver"
        }

        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = session.currentTime
        info[MPMediaItemPropertyPlaybackDuration] = session.duration
        info[MPNowPlayingInfoPropertyPlaybackRate] = session.status == .playing ? Double(selectedSpeed) : 0.0

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
