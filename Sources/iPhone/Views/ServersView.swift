import SwiftUI

/// View for managing personal Emby & Jellyfin media servers.
public struct ServersView: View {
    @ObservedObject var serverManager = MediaServerManager.shared
    @State private var isShowingAddServerSheet = false

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                if serverManager.savedServers.isEmpty {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "server.rack")
                                .font(.system(size: 44))
                                .foregroundColor(.cyan)
                                .padding(.top, 16)

                            Text("No Media Servers Added")
                                .font(.headline)

                            Text("Connect your personal Emby or Jellyfin server to browse and stream your personal movies and TV shows directly on iPhone and CarPlay.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)

                            Button {
                                isShowingAddServerSheet = true
                            } label: {
                                Label("Add Emby / Jellyfin Server", systemImage: "plus.circle.fill")
                                    .font(.subheadline.bold())
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.cyan)
                            .padding(.bottom, 16)
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    Section("Your Connected Servers") {
                        ForEach(serverManager.savedServers) { server in
                            NavigationLink {
                                ServerDetailView(serverInfo: server)
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: server.serverType == .emby ? "tv.fill" : "play.square.stack.fill")
                                        .font(.title2)
                                        .foregroundColor(.cyan)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(server.name)
                                            .font(.headline)
                                        Text(server.url.absoluteString)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                let id = serverManager.savedServers[index].id
                                serverManager.removeServer(id: id)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Media Servers")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingAddServerSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isShowingAddServerSheet) {
                AddServerView()
            }
        }
    }
}

// MARK: - Add Server Sheet

struct AddServerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var serverName = ""
    @State private var serverUrlStr = ""
    @State private var serverType: MediaServerType = .jellyfin
    @State private var username = ""
    @State private var password = ""
    @State private var isAuthenticating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Server Connection") {
                    Picker("Server Type", selection: $serverType) {
                        Text("Jellyfin").tag(MediaServerType.jellyfin)
                        Text("Emby").tag(MediaServerType.emby)
                    }
                    .pickerStyle(.segmented)

                    TextField("Server Name (e.g. Home Server)", text: $serverName)
                    TextField("Server URL (http://192.168.1.10:8096)", text: $serverUrlStr)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .keyboardType(.URL)
                }

                Section("Credentials") {
                    TextField("Username", text: $username)
                        .autocapitalization(.none)
                    SecureField("Password", text: $password)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Add Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect") {
                        connectServer()
                    }
                    .disabled(isAuthenticating || serverUrlStr.isEmpty || username.isEmpty)
                }
            }
        }
    }

    private func connectServer() {
        guard let url = URL(string: serverUrlStr.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            errorMessage = "Invalid server URL."
            return
        }
        let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)

        isAuthenticating = true
        errorMessage = nil

        let name = serverName.isEmpty ? (url.host ?? "Media Server") : serverName

        Task {
            if serverType == .emby {
                let client = EmbyClient(serverName: name, serverBaseURL: url)
                do {
                    let token = try await client.authenticate(username: normalizedUsername, password: password)
                    await MainActor.run {
                        MediaServerManager.shared.addServer(
                            name: name,
                            url: url,
                            type: .emby,
                            username: normalizedUsername,
                            token: token,
                            userId: client.userId
                        )
                        isAuthenticating = false
                        dismiss()
                    }
                } catch {
                    await MainActor.run {
                        errorMessage = error.localizedDescription
                        isAuthenticating = false
                    }
                }
            } else {
                let client = JellyfinClient(serverName: name, serverBaseURL: url)
                do {
                    let token = try await client.authenticate(username: username, password: password)
                    await MainActor.run {
                        MediaServerManager.shared.addServer(
                            name: name,
                            url: url,
                            type: .jellyfin,
                            username: username,
                            token: token,
                            userId: client.userId
                        )
                        isAuthenticating = false
                        dismiss()
                    }
                } catch {
                    await MainActor.run {
                        errorMessage = error.localizedDescription
                        isAuthenticating = false
                    }
                }
            }
        }
    }
}
