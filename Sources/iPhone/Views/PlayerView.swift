import SwiftUI
import AVKit
import MediaPlayer

/// SwiftUI Video Player View embedding native AVPlayer and custom playback overlay.
public struct PlayerView: View {
    @ObservedObject var playerService = PlayerService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isControlsVisible = true
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var isScrubbing = false
    @State private var scrubTime: TimeInterval = 0

    public init() {}

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Native AVPlayer View
            CustomVideoPlayer(player: playerService.player)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isControlsVisible.toggle()
                    }
                    if isControlsVisible {
                        scheduleHideControls()
                    }
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

    private var controlsOverlay: some View {
        VStack(spacing: 0) {
            // Top Bar
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.down.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.85))
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
                .padding(.leading, 8)

                Spacer()

                // AirPlay Route Picker
                AirPlayRoutePickerView()
                    .frame(width: 40, height: 40)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .background(
                LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom)
            )

            Spacer()

            // Center Play/Pause & Seek Buttons
            HStack(spacing: 40) {
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
                // Slider
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
                .tint(.blue)

                HStack {
                    Text(SOAPParser.formatUPnPTime(currentTime))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.white.opacity(0.8))

                    Spacer()

                    if playerService.session.isLiveStream {
                        Text("LIVE")
                            .font(.caption.bold())
                            .foregroundColor(.red)
                    } else {
                        Text(SOAPParser.formatUPnPTime(duration))
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .background(
                LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
            )
        }
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
}

// MARK: - AVPlayer Layer Wrapper

public struct CustomVideoPlayer: UIViewControllerRepresentable {
    public let player: AVPlayer

    public init(player: AVPlayer) {
        self.player = player
    }

    public func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspect
        controller.allowsPictureInPicturePlayback = true
        controller.updatesNowPlayingInfoCenter = false // Managed centrally by PlayerService
        return controller
    }

    public func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== player {
            uiViewController.player = player
        }
    }
}

// MARK: - AirPlay Button Wrapper

public struct AirPlayRoutePickerView: UIViewRepresentable {
    public init() {}

    public func makeUIView(context: Context) -> AVRoutePickerView {
        let routePicker = AVRoutePickerView()
        routePicker.tintColor = .white
        routePicker.activeTintColor = .systemBlue
        routePicker.prioritizesVideoDevices = true
        return routePicker
    }

    public func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
