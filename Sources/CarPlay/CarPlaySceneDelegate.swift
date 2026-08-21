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
    @Published public private(set) var isVideoPlaybackAvailable: Bool = false

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
    }

    // MARK: - CPSessionConfigurationDelegate

    public func sessionConfiguration(_ sessionConfiguration: CPSessionConfiguration, limitedUserInterfacesChanged limitedUserInterfaces: CPLimitableUserInterface) {
        logger.info("CarPlay limited user interfaces changed: \(limitedUserInterfaces.rawValue)")
        refreshCarPlayUI()
    }

    // MARK: - Vehicle State Inspection

    private func updateVehicleCapabilities() {
        guard let sessionConfiguration else {
            self.isVideoPlaybackAvailable = false
            return
        }
        self.isVideoPlaybackAvailable = CarPlayVideoPresentation.isVideoPlaybackSupported(sessionConfiguration: sessionConfiguration)
    }

    private func refreshCarPlayUI() {
        guard let interfaceController = interfaceController else { return }
        let newRoot = CarPlayTemplateBuilder.buildRootTemplate(interfaceController: interfaceController)
        interfaceController.setRootTemplate(newRoot, animated: false, completion: nil)
    }
}
