import Foundation
import AVFoundation
import MediaPlayer
import OSLog
import Combine

private let logger = Logger(subsystem: "com.kelvinsze.vimu", category: "PlayerService")

/// Core video playback service for Vimu, managing AVPlayer, audio session,
/// Now Playing info, and remote control events.
@MainActor
public final class PlayerService: ObservableObject {
    public static let shared = PlayerService()

    @Published public private(set) var session: PlaybackSession = PlaybackSession()
    @Published public private(set) var player: AVPlayer

    private var timeObserverToken: Any?
    private var itemStatusObserver: NSKeyValueObservation?
    private var itemLoadedRangesObserver: NSKeyValueObservation?
    private var playerTimeControlObserver: NSKeyValueObservation?
    private var cancellables = Set<AnyCancellable>()

    public init() {
        let avPlayer = AVPlayer()
        avPlayer.allowsExternalPlayback = true
        avPlayer.usesExternalPlaybackWhileExternalScreenIsActive = true
        avPlayer.automaticallyWaitsToMinimizeStalling = true
        self.player = avPlayer

        setupAudioSession()
        setupRemoteCommands()
        setupNotifications()
        setupPeriodicTimeObserver()
    }

    // MARK: - Audio Session

    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay, .allowBluetooth, .allowBluetoothA2DP])
            try audioSession.setActive(true)
            logger.info("AVAudioSession configured for background video playback.")
        } catch {
            logger.error("Failed to configure AVAudioSession: \(error.localizedDescription)")
        }
    }

    // MARK: - Playback Control

    public func loadAndPlay(item: MediaItem) {
        logger.info("Loading media item: \(item.title) (\(item.url.absoluteString))")

        // Invalidate previous item observations
        itemStatusObserver?.invalidate()
        itemLoadedRangesObserver?.invalidate()

        // Create asset and player item
        let asset: AVURLAsset
        if let headers = item.headers, !headers.isEmpty {
            asset = AVURLAsset(url: item.url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        } else {
            asset = AVURLAsset(url: item.url)
        }

        let playerItem = AVPlayerItem(asset: asset)
        playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = true

        // Update session
        session.currentItem = item
        session.status = .loading
        session.currentTime = 0
        session.duration = item.duration ?? 0
        session.bufferedTime = 0
        session.errorMessage = nil

        // Observe player item status
        itemStatusObserver = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                self?.handleItemStatusChange(item)
            }
        }

        // Observe loaded time ranges (buffering)
        itemLoadedRangesObserver = playerItem.observe(\.loadedTimeRanges, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                self?.handleLoadedTimeRangesChange(item)
            }
        }

        // Replace current item and play
        player.replaceCurrentItem(with: playerItem)
        player.play()

        // Record into history
        PlaybackHistory.shared.addOrUpdate(item: item)
        updateNowPlayingInfo()
    }

    public func play() {
        guard session.currentItem != nil else { return }
        player.play()
        session.status = .playing
        updateNowPlayingInfo()
    }

    public func pause() {
        player.pause()
        session.status = .paused
        updateNowPlayingInfo()
    }

    public func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
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

    public func seek(to seconds: TimeInterval) {
        let targetSeconds = max(0, min(seconds, session.duration > 0 ? session.duration : seconds))
        let targetTime = CMTime(seconds: targetSeconds, preferredTimescale: 600)
        
        // Precise seek with zero tolerance for smoother seeking
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            guard finished else { return }
            Task { @MainActor [weak self] in
                self?.session.currentTime = targetSeconds
                self?.updateNowPlayingInfo()
            }
        }
    }

    public func seek(by deltaSeconds: TimeInterval) {
        let target = session.currentTime + deltaSeconds
        seek(to: target)
    }

    public func setRate(_ rate: Float) {
        session.playbackRate = rate
        if session.status == .playing {
            player.rate = rate
        }
    }

    public func setVolume(_ volume: Float) {
        let clamped = max(0.0, min(volume, 1.0))
        player.volume = clamped
        session.volume = clamped
    }

    public func setMuted(_ isMuted: Bool) {
        player.isMuted = isMuted
        session.isMuted = isMuted
    }

    // MARK: - Observers & Handlers

    private func setupPeriodicTimeObserver() {
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let current = CMTimeGetSeconds(time)
                if current.isFinite && !current.isNaN {
                    self.session.currentTime = max(0, current)
                }
            }
        }

        playerTimeControlObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                switch player.timeControlStatus {
                case .playing:
                    self.session.status = .playing
                case .paused:
                    if self.session.status != .stopped && self.session.status != .failed {
                        self.session.status = .paused
                    }
                case .waitingToPlayAtSpecifiedRate:
                    self.session.status = .loading
                @unknown default:
                    break
                }
                self.updateNowPlayingInfo()
            }
        }
    }

    private func handleItemStatusChange(_ item: AVPlayerItem) {
        switch item.status {
        case .readyToPlay:
            let durationSeconds = CMTimeGetSeconds(item.duration)
            if durationSeconds.isFinite && !durationSeconds.isNaN {
                session.duration = max(0, durationSeconds)
            }
            session.status = .playing
            logger.info("Media ready to play. Duration: \(self.session.duration)s")
            updateNowPlayingInfo()
        case .failed:
            let err = item.error?.localizedDescription ?? "Unknown playback error"
            session.status = .failed
            session.errorMessage = err
            logger.error("Media failed to play: \(err)")
        case .unknown:
            session.status = .loading
        @unknown default:
            break
        }
    }

    private func handleLoadedTimeRangesChange(_ item: AVPlayerItem) {
        guard let timeRange = item.loadedTimeRanges.first?.timeRangeValue else { return }
        let bufferedSeconds = CMTimeGetSeconds(CMTimeAdd(timeRange.start, timeRange.duration))
        if bufferedSeconds.isFinite && !bufferedSeconds.isNaN {
            session.bufferedTime = bufferedSeconds
        }
    }

    private func setupNotifications() {
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    logger.info("Reached end of media playback.")
                    self?.session.status = .stopped
                    self?.updateNowPlayingInfo()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime)
            .sink { [weak self] notification in
                Task { @MainActor [weak self] in
                    let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                    let message = error?.localizedDescription ?? "Playback failed before ending."
                    self?.session.status = .failed
                    self?.session.errorMessage = message
                    logger.error("Player item failed to play to end: \(message)")
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .sink { [weak self] notification in
                Task { @MainActor [weak self] in
                    self?.handleAudioInterruption(notification)
                }
            }
            .store(in: &cancellables)
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
                self?.seek(by: skipEvent.interval)
            }
            return .success
        }

        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { [weak self] event in
            guard let skipEvent = event as? MPSkipIntervalCommandEvent else { return .commandFailed }
            Task { @MainActor [weak self] in
                self?.seek(by: -skipEvent.interval)
            }
            return .success
        }

        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor [weak self] in
                self?.seek(to: positionEvent.positionTime)
            }
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        var info: [String: Any] = [:]
        if let currentItem = session.currentItem {
            info[MPMediaItemPropertyTitle] = currentItem.title
            info[MPMediaItemPropertyArtist] = currentItem.originator ?? "Vimu Receiver"
        }

        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = session.currentTime
        info[MPMediaItemPropertyPlaybackDuration] = session.duration
        info[MPNowPlayingInfoPropertyPlaybackRate] = session.status == .playing ? 1.0 : 0.0

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
