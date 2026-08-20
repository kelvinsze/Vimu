import Foundation
import CarPlay
import Combine
import OSLog

private let logger = Logger(subsystem: "com.kelvinsze.vimu", category: "CarPlaySceneDelegate")

/// CarPlay Application Scene Delegate managing the automotive lifecycle and interface controller.
public final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate, CPSessionConfigurationDelegate {

    public var interfaceController: CPInterfaceController?
    private var sessionConfiguration: CPSessionConfiguration?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - CPTemplateApplicationSceneDelegate

    public func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {
        logger.info("CarPlay connected.")
        self.interfaceController = interfaceController

        // Initialize session configuration to monitor vehicle driving state
        self.sessionConfiguration = CPSessionConfiguration(delegate: self)

        // Build initial root template
        refreshCarPlayUI()

        // Observe player session changes to update CarPlay UI dynamically
        Task { @MainActor in
            PlayerService.shared.$session
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.refreshCarPlayUI()
                }
                .store(in: &self.cancellables)
        }
    }

    public func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        logger.info("CarPlay disconnected.")
        self.interfaceController = nil
        self.sessionConfiguration = nil
        cancellables.removeAll()
        Task { @MainActor in
            CarPlayVideoPresentation.shared.detachVideo()
        }
    }

    // MARK: - CPSessionConfigurationDelegate

    public func sessionConfiguration(_ sessionConfiguration: CPSessionConfiguration, limitedUserInterfacesChanged limitedUserInterfaces: CPLimitableUserInterface) {
        logger.info("CarPlay limited interfaces changed: \(limitedUserInterfaces.rawValue)")
    }

    // MARK: - Private Helpers

    private func refreshCarPlayUI() {
        guard let interfaceController = interfaceController else { return }
        Task { @MainActor in
            let newRoot = CarPlayTemplateBuilder.buildRootTemplate(interfaceController: interfaceController)
            interfaceController.setRootTemplate(newRoot, animated: false, completion: nil)
        }
    }
}
