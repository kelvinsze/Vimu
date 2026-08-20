import SwiftUI

/// Main TabView uniting Player, Media Servers, Diagnostics, and Settings.
public struct MainTabView: View {
    public init() {}

    public var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Player", systemImage: "play.tv.fill")
                }

            ServersView()
                .tabItem {
                    Label("Servers", systemImage: "server.rack")
                }

            DiagnosticsView()
                .tabItem {
                    Label("Diagnostics", systemImage: "waveform.path.ecg")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .tint(.cyan)
    }
}
