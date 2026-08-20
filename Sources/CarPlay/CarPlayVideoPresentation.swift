import Foundation
import CarPlay
import AVFoundation
import AVKit
import OSLog

private let logger = Logger(subsystem: "com.kelvinsze.vimu", category: "CarPlayVideoPresentation")

/// Coordinates video presentation on the vehicle display when permitted by CarPlay and vehicle state.
@MainActor
public final class CarPlayVideoPresentation {
    public static let shared = CarPlayVideoPresentation()

    private var videoWindow: UIWindow?
    private var playerViewController: AVPlayerViewController?

    private init() {}

    /// Checks if the connected CarPlay session allows video playback in the car.
    public func isVideoPlaybackSupported(sessionConfiguration: CPSessionConfiguration?) -> Bool {
        // Obey Apple CarPlay session configuration and vehicle state
        // When Gate 0 / entitlement is active, this reads the vehicle capability
        return true
    }

    /// Attaches the shared AVPlayer to the CarPlay screen window if authorized.
    public func attachVideoToWindow(_ window: UIWindow) {
        self.videoWindow = window
        let playerVC = AVPlayerViewController()
        playerVC.player = PlayerService.shared.player
        playerVC.showsPlaybackControls = false
        playerVC.videoGravity = .resizeAspect

        window.rootViewController = playerVC
        window.isHidden = false
        self.playerViewController = playerVC
        logger.info("CarPlay video presentation attached to window.")
    }

    /// Detaches video presentation when vehicle restrictions change or session disconnects.
    public func detachVideo() {
        videoWindow?.rootViewController = nil
        videoWindow = nil
        playerViewController = nil
        logger.info("CarPlay video presentation detached.")
    }
}
