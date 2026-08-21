import Foundation
import CarPlay
import Combine
import OSLog

private let logger = Logger(subsystem: "com.kelvinsze.vimu", category: "CarPlaySceneDelegate")

/// CarPlay Application Scene Delegate managing automotive lifecycle, vehicle state, and interface controller.
@MainActor
public final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate, CPSessionConfigurationDelegate, ObservableObject {
    public static var shared: CarPlaySceneDelegate?

    public var interfaceController: CPInterfaceController?
    private var sessionConfiguration: CPSessionConfiguration?
    private var cancellables = Set<AnyCancellable>()

    @Published public private(set) var isConnected: Bool = false
    @Published public private(set) var isVideoPlaybackAvailable: Bool = true
    @Published public private(set) var isDrivingRestricted: Bool = false

    override public init() {
        super.init()
        CarPlaySceneDelegate.shared = self
    }

    // MARK: - CPTemplateApplicationSceneDelegate

    public func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {
        logger.info("CarPlay connected to vehicle multimedia unit.")
        self.interfaceController = interfaceController
        self.isConnected = true

        // Initialize session configuration to monitor vehicle driving state
        self.sessionConfiguration = CPSessionConfiguration(delegate: self)
        updateVehicleCapabilities()

        // Build initial root template
        refreshCarPlayUI()

        // Observe player session changes to update CarPlay UI dynamically
        PlayerService.shared.$session
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshCarPlayUI()
            }
            .store(in: &self.cancellables)
    }

    public func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        logger.info("CarPlay disconnected from vehicle.")
        self.interfaceController = nil
        self.sessionConfiguration = nil
        self.isConnected = false
        cancellables.removeAll()
        CarPlayVideoPresentation.shared.detachVideo()
    }

    // MARK: - CPSessionConfigurationDelegate

    public func sessionConfiguration(_ sessionConfiguration: CPSessionConfiguration, limitedUserInterfacesChanged limitedUserInterfaces: CPLimitableUserInterface) {
        let isRestricted = !limitedUserInterfaces.isEmpty
        self.isDrivingRestricted = isRestricted
        logger.info("CarPlay driving limits changed. Restricted: \(isRestricted)")

        if isRestricted {
            // Vehicle is in motion -> strictly pause or mute video display according to safety rules
            if PlayerService.shared.session.status == .playing {
                logger.info("Vehicle in motion: Pausing video playback for automotive safety.")
                PlayerService.shared.pause()
            }
        }
        refreshCarPlayUI()
    }

    // MARK: - Vehicle State Inspection

    private func updateVehicleCapabilities() {
        // CPSessionConfiguration monitors the car's current state
        self.isVideoPlaybackAvailable = true
    }

    private func refreshCarPlayUI() {
        guard let interfaceController = interfaceController else { return }
        let newRoot = CarPlayTemplateBuilder.buildRootTemplate(interfaceController: interfaceController)
        interfaceController.setRootTemplate(newRoot, animated: false, completion: nil)
    }
}
