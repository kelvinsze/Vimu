import Foundation
import AVFoundation

/// Native AVPlayer adapter used during the migration to PlaybackCore.
///
/// Keeping this adapter behind `PlayerEngine` lets a future MPV adapter be
/// introduced without changing PlayerService, DLNA, CarPlay, or UI callers.
@MainActor
public final class AVPlayerEngine: PlayerEngine {
    public let player: AVPlayer
    public let renderSurfaceKind: PlaybackRenderSurfaceKind = .nativeAVPlayer
    public private(set) var snapshot = PlaybackEngineSnapshot()
    public let events: AsyncStream<PlaybackEngineEvent>

    private var eventContinuation: AsyncStream<PlaybackEngineEvent>.Continuation?
    private var timeObserverToken: Any?
    private var itemStatusObserver: NSKeyValueObservation?
    private var itemLoadedRangesObserver: NSKeyValueObservation?
    private var itemBufferEmptyObserver: NSKeyValueObservation?
    private var itemBufferKeepUpObserver: NSKeyValueObservation?
    private var itemPresentationSizeObserver: NSKeyValueObservation?
    private var playerTimeControlObserver: NSKeyValueObservation?
    private var notificationTokens: [NSObjectProtocol] = []
    private var pendingSubtitleTrack: SubtitleTrack?
    private var smbResourceLoader: SMBAssetResourceLoader?

    public init(player: AVPlayer = AVPlayer()) {
        var continuation: AsyncStream<PlaybackEngineEvent>.Continuation?
        let eventStream = AsyncStream<PlaybackEngineEvent> { streamContinuation in
            continuation = streamContinuation
        }
        self.player = player
        self.events = eventStream
        self.eventContinuation = continuation

        player.allowsExternalPlayback = true
        player.externalPlaybackVideoGravity = .resizeAspect
        player.automaticallyWaitsToMinimizeStalling = true

        setupPeriodicTimeObserver()
        setupNotifications()
    }

    deinit {
        if let timeObserverToken {
            player.removeTimeObserver(timeObserverToken)
        }
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
        eventContinuation?.finish()
    }

    public func load(_ request: PlaybackRequest) {
        invalidateCurrentItemObservers()

        let asset: AVURLAsset
        if let resourceLoader = SMBAssetResourceLoader(url: request.url) {
            smbResourceLoader = resourceLoader
            asset = resourceLoader.makeAsset()
        } else if request.headers.isEmpty {
            smbResourceLoader = nil
            asset = AVURLAsset(url: request.url)
        } else {
            smbResourceLoader = nil
            asset = AVURLAsset(url: request.url, options: ["AVURLAssetHTTPHeaderFieldsKey": request.headers])
        }

        let playerItem = AVPlayerItem(asset: asset)
        playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        installItemObservers(for: playerItem)

        updateSnapshot {
            $0.status = .loading
            $0.currentTime = request.startPosition
            $0.duration = 0
            $0.bufferedTime = 0
            $0.errorMessage = nil
        }

        player.replaceCurrentItem(with: playerItem)
        if request.startPosition > 0 {
            player.seek(
                to: CMTime(seconds: request.startPosition, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
        }
        player.rate = snapshot.playbackRate
        player.volume = snapshot.volume
        player.isMuted = snapshot.isMuted
        player.play()
    }

    public func play() {
        guard player.currentItem != nil else { return }
        player.rate = snapshot.playbackRate
        player.play()
        updateSnapshot { $0.status = .playing; $0.errorMessage = nil }
    }

    public func pause() {
        player.pause()
        updateSnapshot { $0.status = .paused }
    }

    public func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        smbResourceLoader = nil
        invalidateCurrentItemObservers()
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
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] finished in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if finished {
                    self.updateSnapshot { $0.currentTime = target }
                }
                self.eventContinuation?.yield(.diagnostic(.seekCompleted(target: target, finished: finished)))
            }
        }
    }

    public func setPlaybackRate(_ rate: Float) {
        let clamped = max(0.1, rate)
        updateSnapshot { $0.playbackRate = clamped }
        if snapshot.status == .playing {
            player.rate = clamped
        }
    }

    public func setVolume(_ volume: Float) {
        let clamped = max(0, min(volume, 1))
        player.volume = clamped
        updateSnapshot { $0.volume = clamped }
    }

    public func setMuted(_ isMuted: Bool) {
        player.isMuted = isMuted
        updateSnapshot { $0.isMuted = isMuted }
    }

    public func setSubtitleTrack(_ track: SubtitleTrack?) {
        pendingSubtitleTrack = track
        guard let item = player.currentItem else { return }
        let asset = item.asset
        Task { @MainActor [weak self, weak item] in
            guard let self,
                  let item,
                  self.player.currentItem === item,
                  self.pendingSubtitleTrack == track,
                  let group = try? await asset.loadMediaSelectionGroup(for: .legible),
                  self.player.currentItem === item,
                  self.pendingSubtitleTrack == track else { return }
            self.applySubtitleTrack(track, to: item, in: group)
        }
    }

    private func applySubtitleTrack(_ track: SubtitleTrack?, to item: AVPlayerItem, in group: AVMediaSelectionGroup) {
        if track == nil {
            item.select(nil, in: group)
            return
        }
        let index = Int(track!.id) ?? -1
        var selectedOption: AVMediaSelectionOption?
        for (offset, option) in group.options.enumerated() {
            if option.extendedLanguageTag == track!.language || option.displayName == track!.title {
                selectedOption = option
                break
            }
            if offset == index {
                selectedOption = option
            }
        }
        item.select(selectedOption, in: group)
    }

    private func updateSnapshot(_ update: (inout PlaybackEngineSnapshot) -> Void) {
        var next = snapshot
        update(&next)
        snapshot = next
        eventContinuation?.yield(.snapshot(next))
    }

    private func invalidateCurrentItemObservers() {
        itemStatusObserver?.invalidate()
        itemLoadedRangesObserver?.invalidate()
        itemBufferEmptyObserver?.invalidate()
        itemBufferKeepUpObserver?.invalidate()
        itemPresentationSizeObserver?.invalidate()
        itemStatusObserver = nil
        itemLoadedRangesObserver = nil
        itemBufferEmptyObserver = nil
        itemBufferKeepUpObserver = nil
        itemPresentationSizeObserver = nil
    }

    private func installItemObservers(for item: AVPlayerItem) {
        itemStatusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in self?.handleItemStatusChange(item) }
        }
        itemLoadedRangesObserver = item.observe(\.loadedTimeRanges, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in self?.handleLoadedTimeRangesChange(item) }
        }
        itemBufferEmptyObserver = item.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] item, _ in
            guard item.isPlaybackBufferEmpty else { return }
            Task { @MainActor [weak self] in
                guard let self, item === self.player.currentItem else { return }
                self.updateSnapshot { $0.status = .loading }
            }
        }
        itemBufferKeepUpObserver = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            guard item.isPlaybackLikelyToKeepUp else { return }
            Task { @MainActor [weak self] in
                guard let self, item === self.player.currentItem, self.snapshot.status == .loading else { return }
                self.play()
            }
        }
        itemPresentationSizeObserver = item.observe(\.presentationSize, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self, item === self.player.currentItem else { return }
                self.eventContinuation?.yield(.diagnostic(.presentationSize(
                    width: Double(item.presentationSize.width),
                    height: Double(item.presentationSize.height)
                )))
            }
        }
    }

    private func setupPeriodicTimeObserver() {
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let current = CMTimeGetSeconds(time)
                guard current.isFinite, !current.isNaN else { return }
                self.updateSnapshot { $0.currentTime = max(0, current) }
            }
        }

        playerTimeControlObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch player.timeControlStatus {
                case .playing:
                    self.updateSnapshot { $0.status = .playing }
                case .paused:
                    if self.snapshot.status != .stopped && self.snapshot.status != .failed {
                        self.updateSnapshot { $0.status = .paused }
                    }
                case .waitingToPlayAtSpecifiedRate:
                    self.updateSnapshot { $0.status = .loading }
                @unknown default:
                    break
                }
                self.eventContinuation?.yield(.diagnostic(.timeControl(
                    rawValue: player.timeControlStatus.rawValue,
                    waitingReason: player.reasonForWaitingToPlay?.rawValue
                )))
            }
        }
    }

    private func setupNotifications() {
        let center = NotificationCenter.default
        notificationTokens.append(center.addObserver(forName: .AVPlayerItemTimeJumped, object: nil, queue: .main) { [weak self] notification in
            let notification = notification
            Task { @MainActor [weak self] in
                guard let self, let item = notification.object as? AVPlayerItem, item === self.player.currentItem else { return }
                self.eventContinuation?.yield(.diagnostic(.timeJump))
            }
        })
        notificationTokens.append(center.addObserver(forName: .AVPlayerItemNewErrorLogEntry, object: nil, queue: .main) { [weak self] notification in
            let notification = notification
            Task { @MainActor [weak self] in
                guard let self, let item = notification.object as? AVPlayerItem,
                      item === self.player.currentItem, let event = item.errorLog()?.events.last else { return }
                self.eventContinuation?.yield(.diagnostic(.streamError(domain: event.errorDomain, code: event.errorStatusCode)))
            }
        })
        notificationTokens.append(center.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] notification in
            let notification = notification
            Task { @MainActor [weak self] in
                guard let self, let item = notification.object as? AVPlayerItem, item === self.player.currentItem else { return }
                self.updateSnapshot { $0.status = .stopped }
                self.eventContinuation?.yield(.ended)
            }
        })
        notificationTokens.append(center.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: nil, queue: .main) { [weak self] notification in
            let notification = notification
            Task { @MainActor [weak self] in
                guard let self, let item = notification.object as? AVPlayerItem, item === self.player.currentItem else { return }
                let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                let message = error?.localizedDescription ?? "Playback failed before ending."
                let nsError = error as NSError?
                self.updateSnapshot { $0.status = .failed; $0.errorMessage = message }
                self.eventContinuation?.yield(.diagnostic(.failedToPlayToEnd(
                    message: message,
                    domain: nsError?.domain ?? "unknown",
                    code: nsError?.code ?? 0
                )))
            }
        })
    }

    private func handleItemStatusChange(_ item: AVPlayerItem) {
        guard item === player.currentItem else { return }
        let duration = CMTimeGetSeconds(item.duration)
        let safeDuration = duration.isFinite && !duration.isNaN ? max(0, duration) : 0
        switch item.status {
        case .readyToPlay:
            if let pendingSubtitleTrack { setSubtitleTrack(pendingSubtitleTrack) }
            updateSnapshot { $0.status = .playing; $0.duration = safeDuration; $0.errorMessage = nil }
            eventContinuation?.yield(.diagnostic(.itemStatus(rawValue: item.status.rawValue, duration: safeDuration, errorMessage: nil)))
        case .failed:
            let message = item.error?.localizedDescription ?? "Unknown playback error"
            updateSnapshot { $0.status = .failed; $0.errorMessage = message }
            eventContinuation?.yield(.diagnostic(.itemStatus(rawValue: item.status.rawValue, duration: safeDuration, errorMessage: message)))
        case .unknown:
            updateSnapshot { $0.status = .loading }
            eventContinuation?.yield(.diagnostic(.itemStatus(rawValue: item.status.rawValue, duration: safeDuration, errorMessage: nil)))
        @unknown default:
            break
        }
    }

    private func handleLoadedTimeRangesChange(_ item: AVPlayerItem) {
        guard item === player.currentItem else { return }
        guard let timeRange = item.loadedTimeRanges.first?.timeRangeValue else { return }
        let buffered = CMTimeGetSeconds(CMTimeAdd(timeRange.start, timeRange.duration))
        guard buffered.isFinite, !buffered.isNaN else { return }
        updateSnapshot { $0.bufferedTime = buffered }
    }
}
