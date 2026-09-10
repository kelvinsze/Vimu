import SwiftUI
import AVKit
import MediaPlayer

/// SwiftUI Video Player View embedding native AVPlayer, custom playback overlay,
/// speed selector, aspect ratio toggle, and stream diagnostics HUD.
public struct PlayerView: View {
    @ObservedObject var playerService = PlayerService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isControlsVisible = true
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var isScrubbing = false
    @State private var scrubTime: TimeInterval = 0
    @State private var showDiagnosticsHUD = false

    private let speeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    public init() {}

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            playbackSurface
            .ignoresSafeArea(edges: [.top, .bottom])
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isControlsVisible.toggle()
                }
                if isControlsVisible {
                    scheduleHideControls()
                }
            }

            if playerService.session.status == .failed,
               let errorMessage = playerService.session.errorMessage {
                playbackErrorOverlay(errorMessage)
            }

            // Stream Diagnostics HUD Overlay
            if showDiagnosticsHUD {
                diagnosticsHUD
                    .transition(.opacity)
            }

            // Controls Overlay
            if isControlsVisible {
                controlsOverlay
                    .transition(.opacity)
            }
        }
        .statusBar(hidden: !isControlsVisible)
        .onAppear {
            scheduleHideControls()
        }
    }

    // MARK: - Overlays

    @ViewBuilder
    private var playbackSurface: some View {
#if canImport(MPV)
        if playerService.renderSurfaceKind == .mpvOpenGLES,
           let engine = playerService.activeMPVEngine {
            MPVVideoPlayerView(engine: engine)
        } else {
            CustomVideoPlayer(
                player: playerService.player,
                videoGravity: playerService.videoGravity
            )
        }
#else
        CustomVideoPlayer(
            player: playerService.player,
            videoGravity: playerService.videoGravity
        )
#endif
    }

    private func playbackErrorOverlay(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundColor(.yellow)
            Text("播放失败")
                .font(.headline)
                .foregroundColor(.white)
            Text(message)
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .lineLimit(4)
        }
        .padding(24)
        .background(Color.black.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(32)
    }

    private var controlsOverlay: some View {
        VStack(spacing: 0) {
            // Top Bar
            HStack(spacing: 16) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.down.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.9))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(playerService.session.currentItem?.title ?? "Playing Media")
                        .font(.headline)
                        .foregroundColor(.white)
                        .lineLimit(1)

                    if let originator = playerService.session.currentItem?.originator {
                        Text(originator)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }

                Spacer()

                // Speed Selector Menu
                Menu {
                    ForEach(speeds, id: \.self) { speed in
                        Button {
                            playerService.setRate(speed)
                            scheduleHideControls()
                        } label: {
                            HStack {
                                Text("\(String(format: "%.2fx", speed))")
                                if playerService.selectedSpeed == speed {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Text("\(String(format: "%.1fx", playerService.selectedSpeed))")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(6)
                }

                Menu {
                    Button {
                        playerService.setSubtitleTrack(nil)
                        scheduleHideControls()
                    } label: {
                        HStack { Text("关闭字幕"); if playerService.selectedSubtitleTrack == nil { Image(systemName: "checkmark") } }
                    }
                    if playerService.subtitleTracks.isEmpty {
                        Text("暂无字幕轨道")
                    } else {
                        ForEach(playerService.subtitleTracks) { track in
                            Button {
                                playerService.setSubtitleTrack(track)
                                scheduleHideControls()
                            } label: {
                                HStack {
                                    Text(subtitleLabel(track))
                                    if playerService.selectedSubtitleTrack?.id == track.id { Image(systemName: "checkmark") }
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: playerService.selectedSubtitleTrack == nil ? "captions.bubble" : "captions.bubble.fill")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.9))
                        .padding(6)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Circle())
                }

                if playerService.renderSurfaceKind != .mpvOpenGLES {
                    // Aspect ratio and AirPlay are AVPlayer-only controls.
                    Button {
                        playerService.toggleVideoGravity()
                        scheduleHideControls()
                    } label: {
                        Image(systemName: playerService.videoGravity == .resizeAspect ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
                            .font(.body)
                            .foregroundColor(.white.opacity(0.9))
                            .padding(6)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Circle())
                    }
                }

                // Diagnostics HUD Toggle
                Button {
                    withAnimation {
                        showDiagnosticsHUD.toggle()
                    }
                    scheduleHideControls()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.body)
                        .foregroundColor(showDiagnosticsHUD ? .cyan : .white.opacity(0.9))
                        .padding(6)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Circle())
                }

                if playerService.renderSurfaceKind != .mpvOpenGLES {
                    // MPV's custom surface does not inherit AVPlayer external playback.
                    AirPlayRoutePickerView()
                        .frame(width: 36, height: 36)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 20)
            .background(
                LinearGradient(colors: [.black.opacity(0.75), .clear], startPoint: .top, endPoint: .bottom)
            )

            Spacer()

            // Center Play/Pause & Seek Buttons
            HStack(spacing: 44) {
                Button {
                    playerService.seek(by: -15)
                    scheduleHideControls()
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.system(size: 32))
                        .foregroundColor(.white)
                }

                Button {
                    playerService.togglePlayPause()
                    scheduleHideControls()
                } label: {
                    Image(systemName: playerService.session.status == .playing ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.white)
                }

                Button {
                    playerService.seek(by: 15)
                    scheduleHideControls()
                } label: {
                    Image(systemName: "goforward.15")
                        .font(.system(size: 32))
                        .foregroundColor(.white)
                }
            }

            Spacer()

            // Bottom Progress & Time Bar
            VStack(spacing: 8) {
                let currentTime = isScrubbing ? scrubTime : playerService.session.currentTime
                let duration = max(playerService.session.duration, 1)

                Slider(
                    value: Binding(
                        get: { currentTime },
                        set: { newVal in
                            scrubTime = newVal
                        }
                    ),
                    in: 0...duration,
                    onEditingChanged: { editing in
                        isScrubbing = editing
                        if !editing {
                            playerService.seek(to: scrubTime)
                            scheduleHideControls()
                        }
                    }
                )
                .tint(.cyan)

                HStack {
                    Text(SOAPParser.formatUPnPTime(currentTime))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.white.opacity(0.85))

                    Spacer()

                    if playerService.session.isLiveStream {
                        Text("LIVE")
                            .font(.caption.bold())
                            .foregroundColor(.red)
                    } else {
                        Text(SOAPParser.formatUPnPTime(duration))
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.white.opacity(0.85))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .padding(.top, 16)
            .background(
                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
            )
        }
    }

    private var diagnosticsHUD: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("STREAM HUD")
                .font(.caption2.bold())
                .foregroundColor(.cyan)

            Text("Status: \(playerService.session.status.rawValue)")
                .font(.caption2.monospaced())
                .foregroundColor(.white)

            Text("Position: \(SOAPParser.formatUPnPTime(playerService.session.currentTime)) / \(SOAPParser.formatUPnPTime(playerService.session.duration))")
                .font(.caption2.monospaced())
                .foregroundColor(.white)

            Text("Speed: \(String(format: "%.2fx", playerService.selectedSpeed)) | Gravity: \(playerService.videoGravity == .resizeAspect ? "Aspect" : "Fill")")
                .font(.caption2.monospaced())
                .foregroundColor(.white)

            if let url = playerService.session.currentItem?.url {
                Text("Host: \(url.host ?? "localhost")")
                    .font(.caption2.monospaced())
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(1)
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.75))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.cyan.opacity(0.4), lineWidth: 1)
        )
        .padding(.leading, 16)
        .padding(.top, 80)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func scheduleHideControls() {
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isControlsVisible = false
                }
            }
        }
    }

    private func subtitleLabel(_ track: SubtitleTrack) -> String {
        let base = track.title ?? track.language ?? "字幕 \(track.id)"
        let flags = [track.isDefault ? "默认" : nil, track.isForced ? "强制" : nil].compactMap { $0 }
        let capability = track.format == .pgs || track.format == .vobsub ? "图片" : track.format.rawValue.uppercased()
        return flags.isEmpty ? "\(base) · \(capability)" : "\(base)（\(flags.joined(separator: "、"))）· \(capability)"
    }
}

// MARK: - AVPlayer Layer Wrapper

#if canImport(MPV)
public struct MPVVideoPlayerView: UIViewRepresentable {
    public let engine: MPVPlayerEngine

    public init(engine: MPVPlayerEngine) {
        self.engine = engine
    }

    public func makeUIView(context: Context) -> MPVOpenGLESView {
        engine.makeSurfaceView() ?? MPVOpenGLESView(engine: engine)
    }

    public func updateUIView(_ view: MPVOpenGLESView, context: Context) {
        view.engine = engine
    }
}
#endif

public struct CustomVideoPlayer: UIViewControllerRepresentable {
    public let player: AVPlayer
    public let videoGravity: AVLayerVideoGravity

    public init(player: AVPlayer, videoGravity: AVLayerVideoGravity = .resizeAspect) {
        self.player = player
        self.videoGravity = videoGravity
    }

    public func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = videoGravity
        controller.allowsPictureInPicturePlayback = true
        controller.updatesNowPlayingInfoCenter = false
        return controller
    }

    public func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== player {
            uiViewController.player = player
        }
        if uiViewController.videoGravity != videoGravity {
            uiViewController.videoGravity = videoGravity
        }
    }
}

// MARK: - AirPlay Button Wrapper

public struct AirPlayRoutePickerView: UIViewRepresentable {
    public init() {}

    public func makeUIView(context: Context) -> AVRoutePickerView {
        let routePicker = AVRoutePickerView()
        routePicker.tintColor = .white
        routePicker.activeTintColor = .systemCyan
        routePicker.prioritizesVideoDevices = true
        return routePicker
    }

    public func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
