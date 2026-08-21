import SwiftUI

/// Shows media libraries and video items inside a connected Emby / Jellyfin server.
public struct ServerDetailView: View {
    public let serverInfo: SavedServerInfo
    @ObservedObject var playerService = PlayerService.shared

    @State private var libraries: [MediaLibrary] = []
    @State private var selectedLibrary: MediaLibrary?
    @State private var libraryItems: [MediaItem] = []
    @State private var searchText = ""
    @State private var searchResults: [MediaItem] = []
    @State private var continueWatching: [MediaItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isShowingPlayer = false

    public init(serverInfo: SavedServerInfo) {
        self.serverInfo = serverInfo
    }

    public var body: some View {
        List {
            // MARK: - Libraries Section
            if !continueWatching.isEmpty {
                Section("Continue Watching") {
                    ForEach(continueWatching) { item in
                        Button(item.title) { play(item) }
                    }
                }
            }

            if !searchResults.isEmpty {
                Section("Search Results") {
                    ForEach(searchResults) { item in
                        Button(item.title) { play(item) }
                    }
                }
            }

            if !libraries.isEmpty {
                Section("Media Libraries") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(libraries) { lib in
                                Button {
                                    selectedLibrary = lib
                                    loadItems(for: lib)
                                } label: {
                                    VStack(spacing: 6) {
                                        Image(systemName: iconForCollection(lib.collectionType))
                                            .font(.title2)
                                            .foregroundColor(selectedLibrary?.id == lib.id ? .white : .cyan)
                                        Text(lib.name)
                                            .font(.caption.bold())
                                            .foregroundColor(selectedLibrary?.id == lib.id ? .white : .primary)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(selectedLibrary?.id == lib.id ? Color.cyan : Color(.secondarySystemBackground))
                                    .cornerRadius(10)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            // MARK: - Videos List Section
            Section(selectedLibrary?.name ?? "Videos") {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding()
                } else if libraryItems.isEmpty {
                    Text("No videos found in this library.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(libraryItems) { item in
                        Button {
                            play(item)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "play.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.cyan)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.subheadline.bold())
                                        .foregroundColor(.primary)

                                    if let duration = item.duration {
                                        Text(SOAPParser.formatUPnPTime(duration))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }

            if let error = errorMessage {
                Section {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
        .navigationTitle(serverInfo.name)
        .onAppear {
            loadLibraries()
            loadContinueWatching()
        }
        .searchable(text: $searchText, prompt: "Search media")
        .onSubmit(of: .search) { search() }
        .fullScreenCover(isPresented: $isShowingPlayer) {
            PlayerView()
        }
    }

    // MARK: - Networking

    private func loadLibraries() {
        guard let client = MediaServerManager.shared.getClient(for: serverInfo.id) else { return }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let fetched = try await client.fetchLibraries()
                await MainActor.run {
                    self.libraries = fetched
                    self.isLoading = false
                    if let first = fetched.first {
                        self.selectedLibrary = first
                        loadItems(for: first)
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    private func loadContinueWatching() {
        guard let client = MediaServerManager.shared.getClient(for: serverInfo.id) else { return }
        Task {
            let items = (try? await client.fetchContinueWatching(limit: 10)) ?? []
            await MainActor.run { continueWatching = items }
        }
    }

    private func search() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, let client = MediaServerManager.shared.getClient(for: serverInfo.id) else {
            searchResults = []
            return
        }
        Task {
            let items = (try? await client.search(query: query, limit: 30)) ?? []
            await MainActor.run { searchResults = items }
        }
    }

    private func play(_ item: MediaItem) {
        guard let client = MediaServerManager.shared.getClient(for: serverInfo.id) else { return }
        Task {
            let resolved = (try? await client.resolvePlaybackItem(item)) ?? item
            await MainActor.run {
                playerService.loadAndPlay(item: resolved)
                isShowingPlayer = true
            }
        }
    }

    private func loadItems(for library: MediaLibrary) {
        guard let client = MediaServerManager.shared.getClient(for: serverInfo.id) else { return }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let items = try await client.fetchItems(libraryId: library.id, startIndex: 0, limit: 50)
                await MainActor.run {
                    self.libraryItems = items
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    private func iconForCollection(_ type: String?) -> String {
        switch type?.lowercased() {
        case "movies": return "film"
        case "tvshows": return "tv"
        case "music": return "music.note"
        default: return "play.square.stack"
        }
    }
}
