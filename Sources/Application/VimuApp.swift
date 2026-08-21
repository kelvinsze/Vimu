import SwiftUI
import CarPlay
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

/// Custom AppDelegate managing application lifecycle, scene routing (Phone vs CarPlay), and background services.
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

    // Dynamic scene session configuration routing for CarPlay and Phone
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if connectingSceneSession.role == .carTemplateApplication || connectingSceneSession.role.rawValue == "CPTemplateApplicationSceneSessionRoleApplication" {
            logger.info("Connecting CarPlay scene configuration...")
            let config = UISceneConfiguration(name: "CarPlay Configuration", sessionRole: connectingSceneSession.role)
            config.delegateClass = CarPlaySceneDelegate.self
            return config
        } else {
            logger.info("Connecting Phone UIWindowScene configuration...")
            let config = UISceneConfiguration(name: "Phone Configuration", sessionRole: connectingSceneSession.role)
            config.delegateClass = PhoneSceneDelegate.self
            return config
        }
    }

    func applicationWillTerminate(_ application: UIApplication) {
        logger.info("Vimu terminating. Stopping services...")
        SSDPService.shared.stop()
        HTTPServer.shared.stop()
    }
}
