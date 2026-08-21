import SwiftUI

/// Settings view for configuring UPnP device friendly name, port, and viewing entitlement status.
public struct SettingsView: View {
    @AppStorage("vimu_custom_friendly_name") private var customFriendlyName: String = ""
    @State private var isShowingSavedAlert = false

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                Section("Receiver Configuration") {
                    TextField("Friendly Name (e.g. Vimu Car)", text: $customFriendlyName)
                        .onChange(of: customFriendlyName) { newValue in
                            if !newValue.isEmpty {
                                UPnPDevice.shared.friendlyName = newValue
                            }
                        }

                    HStack {
                        Text("HTTP Port")
                        Spacer()
                        Text("\(HTTPServer.shared.port)")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Device UDN")
                        Spacer()
                        Text(UPnPDevice.shared.udn)
                            .font(.caption2.monospaced())
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Section("Apple Entitlement & Capability Status") {
                    HStack {
                        Text("CarPlay Video Capability")
                        Spacer()
                        Label(
                            "Cannot verify signed entitlement",
                            systemImage: "questionmark.diamond"
                        )
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Multicast Networking")
                        Spacer()
                        Label(
                            "Cannot verify signed entitlement",
                            systemImage: "questionmark.diamond"
                        )
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section("About Vimu") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("0.1.0 (Build 1)")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Target Architecture")
                        Spacer()
                        Text("MediaCore + DLNA + CarPlay Video")
                            .foregroundColor(.secondary)
                    }

                    Link("Privacy Policy", destination: URL(string: "https://vimu.app/privacy")!)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
