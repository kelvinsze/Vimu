import SwiftUI
import OSLog

private let logger = Logger(subsystem: "com.kelvinsze.vimu", category: "VimuApp")

@main
struct VimuApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
    }
}

/// Custom AppDelegate for application lifecycle and global background service bootstrapping.
final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        logger.info("Vimu launching. Initializing DLNA HTTP Server and SSDP Discovery...")

        // Start UPnP HTTP Server on port 7890
        HTTPServer.shared.start(port: 7890)

        // Start SSDP Multicast discovery service on 239.255.255.250:1900
        SSDPService.shared.start()

        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        logger.info("Vimu terminating. Stopping services...")
        SSDPService.shared.stop()
        HTTPServer.shared.stop()
    }
}
