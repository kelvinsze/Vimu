import Foundation
import CarPlay
import Combine
import OSLog

private let logger = Logger(subsystem: "com.kelvinsze.mivu", category: "CarPlaySceneDelegate")

/// CarPlay Application Scene Delegate managing automotive lifecycle, vehicle state, and interface controller.
@MainActor
public final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate, CPSessionConfigurationDelegate, ObservableObject {
    public static var shared: CarPlaySceneDelegate?

    public var interfaceController: CPInterfaceController?
    private var sessionConfiguration: CPSessionConfiguration?
    private var cancellables = Set<AnyCancellable>()
    private var isPresentingRootTemplate = false
    private var needsRootTemplateRefresh = false
    private var shouldPresentIncomingPlayback = false

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

        // CarPlay requires a root template before this callback returns. Keep the
        // first presentation independent from player and media-server startup.
        presentInitialRootTemplate(using: interfaceController)

        // Initialize session configuration to monitor vehicle driving state
        self.sessionConfiguration = CPSessionConfiguration(delegate: self)
        updateVehicleCapabilities()

        if PlayerService.shared.session.currentItem?.sourceType == .dlna {
            shouldPresentIncomingPlayback = true
        }

        // Observe player session changes to update CarPlay UI dynamically
        PlayerService.shared.$session
            .map { session in
                "\(session.currentItem?.id.uuidString ?? "none")|\(session.status.rawValue)"
            }
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.refreshCarPlayUI()
            }
            .store(in: &self.cancellables)
    }

    public func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        logger.info("CarPlay disconnected from vehicle.")
        self.interfaceController = nil
        self.sessionConfiguration = nil
        self.isConnected = false
        self.isPresentingRootTemplate = false
        self.needsRootTemplateRefresh = false
        self.shouldPresentIncomingPlayback = false
        cancellables.removeAll()
    }

    // MARK: - CPSessionConfigurationDelegate

    public func sessionConfiguration(_ sessionConfiguration: CPSessionConfiguration, limitedUserInterfacesChanged limitedUserInterfaces: CPLimitableUserInterface) {
        logger.info("CarPlay limited user interfaces changed: \(limitedUserInterfaces.rawValue)")
        updateVehicleCapabilities()
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
        if PlayerService.shared.session.currentItem?.sourceType == .dlna {
            SSDPService.shared.recordCastDebug("CARPLAY refreshRoot busy=\(isPresentingRootTemplate) incoming=\(shouldPresentIncomingPlayback)")
        }

        guard !isPresentingRootTemplate else {
            needsRootTemplateRefresh = true
            return
        }

        isPresentingRootTemplate = true
        let newRoot = CarPlayTemplateBuilder.buildRootTemplate(interfaceController: interfaceController)
        logger.info("Presenting CarPlay root template with \(newRoot.sections.count) sections.")

        interfaceController.setRootTemplate(newRoot, animated: false) { [weak self] success, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isPresentingRootTemplate = false

                if PlayerService.shared.session.currentItem?.sourceType == .dlna {
                    SSDPService.shared.recordCastDebug("CARPLAY setRoot completed success=\(success)")
                }

                if success {
                    logger.info("CarPlay root template presented successfully.")
                } else {
                    logger.error("CarPlay root template presentation failed: \(error?.localizedDescription ?? "unknown error", privacy: .public)")
                }

                if self.needsRootTemplateRefresh {
                    self.needsRootTemplateRefresh = false
                    self.refreshCarPlayUI()
                } else if success {
                    self.presentPendingIncomingPlayback()
                }
            }
        }
    }

    /// A DLNA sender does not select the CarPlay list item. Refresh the root
    /// list so the user can select its video-configured playback item; pushing
    /// Now Playing alone only exposes controls and never starts video
    /// presentation.
    public func presentIncomingPlayback() {
        shouldPresentIncomingPlayback = true
        guard interfaceController != nil else {
            SSDPService.shared.recordPlaybackStage("等待 CarPlay 连接")
            return
        }
        let capability = isVideoPlaybackAvailable ? "车机支持视频" : "车机未报告视频能力或当前策略受限"
        SSDPService.shared.recordPlaybackStage("已通知 CarPlay（\(capability)）")
        refreshCarPlayUI()
    }

    private func presentPendingIncomingPlayback() {
        guard shouldPresentIncomingPlayback, interfaceController != nil else { return }
        shouldPresentIncomingPlayback = false

        let capability = isVideoPlaybackAvailable ? "车机支持视频" : "车机未报告视频能力或当前策略受限"
        logger.info("Incoming cast is ready for CarPlay video selection.")
        SSDPService.shared.recordPlaybackStage("CarPlay 已显示可选视频条目（\(capability)）")
    }

    private func presentInitialRootTemplate(using interfaceController: CPInterfaceController) {
        let statusItem = CPListItem(
            text: "Mivu 已连接",
            detailText: "正在载入媒体与接收器状态…",
            image: UIImage(systemName: "play.rectangle.fill")
        )
        let initialRoot = CPListTemplate(
            title: "Mivu",
            sections: [CPListSection(items: [statusItem])]
        )

        isPresentingRootTemplate = true
        interfaceController.setRootTemplate(initialRoot, animated: false) { [weak self] success, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isPresentingRootTemplate = false

                if success {
                    logger.info("Initial CarPlay root template presented successfully.")
                    self.refreshCarPlayUI()
                } else {
                    logger.error("Initial CarPlay root template presentation failed: \(error?.localizedDescription ?? "unknown error", privacy: .public)")
                }
            }
        }
    }
}
