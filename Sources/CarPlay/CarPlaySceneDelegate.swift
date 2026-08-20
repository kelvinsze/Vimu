import Foundation
import CarPlay
import OSLog

private let logger = Logger(subsystem: "com.kelvinsze.vimu", category: "CarPlaySceneDelegate")

/// CarPlay Application Scene Delegate managing the automotive lifecycle and interface controller.
public final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate, CPSessionConfigurationDelegate {

    public var interfaceController: CPInterfaceController?
    private var sessionConfiguration: CPSessionConfiguration?

    // MARK: - CPTemplateApplicationSceneDelegate

    public func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {
        logger.info("CarPlay connected.")
        self.interfaceController = interfaceController

        // Initialize session configuration to monitor vehicle driving state
        self.sessionConfiguration = CPSessionConfiguration(delegate: self)

        // Build and display root template
        let rootTemplate = CarPlayTemplateBuilder.buildRootTemplate(interfaceController: interfaceController)
        interfaceController.setRootTemplate(rootTemplate, animated: false, completion: nil)
    }

    public func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        logger.info("CarPlay disconnected.")
        self.interfaceController = nil
        self.sessionConfiguration = nil
        CarPlayVideoPresentation.shared.detachVideo()
    }

    // MARK: - CPSessionConfigurationDelegate

    public func sessionConfiguration(_ sessionConfiguration: CPSessionConfiguration, limitedUserInterfacesChanged limitedUserInterfaces: CPLimitableUserInterface) {
        logger.info("CarPlay limited interfaces changed: \(limitedUserInterfaces.rawValue)")
    }
}
