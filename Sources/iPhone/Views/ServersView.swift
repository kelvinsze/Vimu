import SwiftUI

/// View for managing personal media servers and standard file shares.
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

                            Text("Connect Emby, Jellyfin, WebDAV, SMB, or fnOS WebDAV to browse and stream your personal videos on iPhone and CarPlay.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)

                            Button {
                                isShowingAddServerSheet = true
                            } label: {
                                Label("Add Media Source", systemImage: "plus.circle.fill")
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
                                    Image(systemName: icon(for: server.serverType))
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

    private func icon(for type: MediaServerType) -> String {
        switch type {
        case .emby: return "tv.fill"
        case .jellyfin, .fnos: return "play.square.stack.fill"
        case .webDAV: return "externaldrive.connected.to.line.below"
        case .smb: return "folder.badge.gearshape"
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
                        Text("WebDAV").tag(MediaServerType.webDAV)
                        Text("SMB").tag(MediaServerType.smb)
                        Text("fnOS (WebDAV)").tag(MediaServerType.fnos)
                    }
                    .pickerStyle(.menu)

                    TextField("Server Name (e.g. Home Server)", text: $serverName)
                    TextField(urlPlaceholder, text: $serverUrlStr)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .keyboardType(.URL)
                }

                Section("Credentials") {
                    TextField("Username", text: $username)
                        .autocapitalization(.none)
                    SecureField("Password", text: $password)
                }

                if serverType == .fnos {
                    Section {
                        Text("In fnOS, enable WebDAV under Settings → File Sharing Protocols, then paste its full WebDAV URL here. The fnOS private media API is not used.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if serverType == .smb {
                    Section {
                        Text("Use smb://host/share/folder. SMB 2 is supported; SMB 1 is intentionally excluded.")
                            .font(.caption)
                            .foregroundColor(.secondary)
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

    private var urlPlaceholder: String {
        switch serverType {
        case .emby: return "http://192.168.1.10:8096"
        case .jellyfin: return "http://192.168.1.10:8096"
        case .webDAV, .fnos: return "https://nas.example.com/webdav/"
        case .smb: return "smb://192.168.1.10/Media/Movies"
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
            do {
                let client: MediaServerProtocol
                let userID: String?
                switch serverType {
                case .emby:
                    let emby = EmbyClient(serverName: name, serverBaseURL: url)
                    client = emby; userID = emby.userId
                case .jellyfin:
                    let jellyfin = JellyfinClient(serverName: name, serverBaseURL: url)
                    client = jellyfin; userID = jellyfin.userId
                case .webDAV, .fnos:
                    client = WebDAVClient(serverName: name, serverBaseURL: url, username: normalizedUsername)
                    userID = nil
                case .smb:
                    client = try SMBMediaClient(serverName: name, serverBaseURL: url, username: normalizedUsername)
                    userID = nil
                }
                let token = try await client.authenticate(username: normalizedUsername, password: password)
                let resolvedUserID: String? = {
                    if let emby = client as? EmbyClient { return emby.userId }
                    if let jellyfin = client as? JellyfinClient { return jellyfin.userId }
                    return userID
                }()
                await MainActor.run {
                    MediaServerManager.shared.addServer(name: name, url: url, type: serverType, username: normalizedUsername, token: token, userId: resolvedUserID)
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
