import UIKit
import SwiftUI
import OSLog

private let logger = Logger(subsystem: "com.kelvinsze.mivu", category: "PhoneSceneDelegate")

/// iPhone Window Scene Delegate managing window presentation and deep linking.
public final class PhoneSceneDelegate: UIResponder, UIWindowSceneDelegate {

    public var window: UIWindow?

    public func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: MainTabView())
        self.window = window
        window.makeKeyAndVisible()

        // Handle URL on launch if opened via deep link
        if let url = connectionOptions.urlContexts.first?.url {
            handleIncomingURL(url)
        }
    }

    public func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        if let url = URLContexts.first?.url {
            handleIncomingURL(url)
        }
    }

    private func handleIncomingURL(_ url: URL) {
        logger.info("Opening incoming URL: \(url.absoluteString)")
        if let item = URLSource.parseDeepLink(url: url) {
            Task { @MainActor in
                PlayerService.shared.loadAndPlay(item: item)
            }
        }
    }
}
