import SwiftUI
import Combine

/// Main dashboard view for Mivu iPhone app.
public struct HomeView: View {
    private let playerService = PlayerService.shared
    @ObservedObject var history = PlaybackHistory.shared

    @State private var inputUrlText: String = ""
    @State private var clipboardURL: URL?
    @State private var isShowingPlayerSheet = false
    @State private var errorMessage: String?
    @State private var isShowingErrorAlert = false
    @State private var playbackResolveTask: Task<Void, Never>?
    @State private var playbackResolveID: UUID?

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Receiver Status Banner
                    ReceiverStatusView()

                    // Clipboard Stream Auto-Detection Banner
                    if let detected = clipboardURL {
                        clipboardBanner(detected)
                    }

                    // Direct URL Playback Input
                    directUrlCard

                    // Sample Test Streams
                    sampleStreamsSection

                    // Playback History
                    if !history.items.isEmpty {
                        historySection
                    }
                }
                .padding()
            }
            .navigationTitle("Mivu")
            .onAppear {
                checkClipboard()
            }
            .onReceive(playerService.$session.map { $0.currentItem?.id }.removeDuplicates()) { itemID in
                // DLNA/Web Remote starts playback outside this view's buttons.
                // Personal-media screens own their own player cover; presenting
                // another one here makes the first launch immediately dismiss.
                if itemID != nil,
                   playerService.session.currentItem?.sourceType != .personalMedia {
                    isShowingPlayerSheet = true
                }
            }
            .safeAreaInset(edge: .bottom) {
                HomeMiniPlayerBar(
                    playerService: playerService,
                    isShowingPlayerSheet: $isShowingPlayerSheet
                )
            }
            .fullScreenCover(isPresented: $isShowingPlayerSheet) {
                PlayerView()
            }
            .alert("Playback Error", isPresented: $isShowingErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "An unknown error occurred.")
            }
        }
    }

    // MARK: - Subviews

    private var directUrlCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Play URL / Stream")
                .font(.headline)

            HStack {
                TextField("https://example.com/stream.m3u8", text: $inputUrlText)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .keyboardType(.URL)

                Button {
                    playInputUrl()
                } label: {
                    Image(systemName: "play.fill")
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .disabled(inputUrlText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func clipboardBanner(_ url: URL) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Video URL detected in Clipboard")
                    .font(.caption.bold())
                    .foregroundColor(.blue)
                Text(url.absoluteString)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Play") {
                let item = MediaItem(
                    title: url.lastPathComponent.isEmpty ? "Clipboard Stream" : url.lastPathComponent,
                    url: url,
                    sourceType: .directUrl,
                    originator: "Clipboard"
                )
                playerService.loadAndPlay(item: item)
                isShowingPlayerSheet = true
                clipboardURL = nil
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(12)
        .background(Color.blue.opacity(0.12))
        .cornerRadius(10)
    }

    private var sampleStreamsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sample Test Streams (Phase 1 Validation)")
                .font(.headline)

            VStack(spacing: 8) {
                ForEach(MediaItem.sampleStreams) { sample in
                    Button {
                        playerService.loadAndPlay(item: sample)
                        isShowingPlayerSheet = true
                    } label: {
                        HStack {
                            Image(systemName: sample.mimeType?.contains("mpegURL") == true ? "antenna.radiowaves.left.and.right" : "film")
                                .foregroundColor(.blue)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(sample.title)
                                    .font(.subheadline.bold())
                                    .foregroundColor(.primary)
                                Text(sample.url.absoluteString)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Image(systemName: "play.circle")
                                .foregroundColor(.blue)
                        }
                        .padding(12)
                        .background(Color(.tertiarySystemBackground))
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recently Played")
                    .font(.headline)
                Spacer()
                Button("Clear") {
                    history.clear()
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            VStack(spacing: 8) {
                ForEach(history.items) { item in
                    HStack {
                        Button {
                            playHistoryItem(item)
                        } label: {
                            HStack {
                                Image(systemName: "play.circle.fill")
                                    .foregroundColor(.blue)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.subheadline.bold())
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    Text(item.url.absoluteString)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }

                        Spacer()

                        Button {
                            history.remove(item: item)
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundColor(.red.opacity(0.8))
                        }
                    }
                    .padding(10)
                    .background(Color(.tertiarySystemBackground))
                    .cornerRadius(8)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: - Actions

    private func playHistoryItem(_ item: MediaItem) {
        guard item.sourceType == .personalMedia,
              let serverID = item.serverID,
              let client = MediaServerManager.shared.getClient(for: serverID) else {
            playerService.loadAndPlay(item: item)
            isShowingPlayerSheet = true
            return
        }
        playbackResolveTask?.cancel()
        let resolveID = UUID()
        playbackResolveID = resolveID
        playbackResolveTask = Task {
            do {
                let resolved = try await client.resolvePlaybackItem(item)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard playbackResolveID == resolveID else { return }
                    playbackResolveTask = nil
                    playbackResolveID = nil
                    playerService.loadAndPlay(item: resolved)
                    isShowingPlayerSheet = true
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard playbackResolveID == resolveID else { return }
                    playbackResolveTask = nil
                    playbackResolveID = nil
                    errorMessage = error.localizedDescription
                    isShowingErrorAlert = true
                }
            }
        }
    }

    private func playInputUrl() {
        let trimmed = inputUrlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            errorMessage = "Invalid video URL. Please enter an HTTP or HTTPS stream."
            isShowingErrorAlert = true
            return
        }

        let item = MediaItem(
            title: url.lastPathComponent.isEmpty ? "Direct Stream" : url.lastPathComponent,
            url: url,
            sourceType: .directUrl,
            originator: "User Input"
        )
        playerService.loadAndPlay(item: item)
        isShowingPlayerSheet = true
        inputUrlText = ""
    }

    private func checkClipboard() {
        clipboardURL = URLSource.detectPlayableURLInClipboard()
    }
}

private struct HomeMiniPlayerBar: View {
    @ObservedObject var playerService: PlayerService
    @Binding var isShowingPlayerSheet: Bool

    var body: some View {
        if playerService.session.currentItem != nil {
            HStack {
                Button {
                    isShowingPlayerSheet = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "film.fill")
                            .font(.title3)
                            .foregroundColor(.blue)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(playerService.session.currentItem?.title ?? "Playing Media")
                                .font(.subheadline.bold())
                                .foregroundColor(.primary)
                                .lineLimit(1)

                            Text("\(SOAPParser.formatUPnPTime(playerService.session.currentTime)) / \(SOAPParser.formatUPnPTime(playerService.session.duration))")
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                Button {
                    playerService.togglePlayPause()
                } label: {
                    Image(systemName: playerService.session.status == .playing ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .foregroundColor(.primary)
                        .padding(8)
                }

                Button {
                    playerService.stop()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                        .padding(8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .cornerRadius(14)
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }
}
