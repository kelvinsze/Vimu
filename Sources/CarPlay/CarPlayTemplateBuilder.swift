import Foundation
import CarPlay
import OSLog

private let logger = Logger(subsystem: "com.kelvinsze.vimu", category: "CarPlayTemplateBuilder")

/// Builds CPListTemplates and action sheets for CarPlay UI.
@MainActor
public final class CarPlayTemplateBuilder {

    public static func buildRootTemplate(interfaceController: CPInterfaceController) -> CPListTemplate {
        let nowPlayingItem = CPListItem(
            text: "Now Playing",
            detailText: PlayerService.shared.session.currentItem?.title ?? "No media loaded",
            image: UIImage(systemName: "play.circle.fill")
        )
        nowPlayingItem.handler = { _, completion in
            // Handle Now Playing selection
            completion()
        }

        // Recent Casts / Samples
        let sampleItems = MediaItem.sampleStreams.map { sample in
            let item = CPListItem(
                text: sample.title,
                detailText: sample.mimeType?.contains("mpegURL") == true ? "HLS Live Stream" : "MP4 Video",
                image: UIImage(systemName: "film.fill")
            )
            item.handler = { _, completion in
                PlayerService.shared.loadAndPlay(item: sample)
                completion()
            }
            return item
        }

        let sectionMedia = CPListSection(items: [nowPlayingItem] + sampleItems, header: "Vimu Media", sectionIndexTitle: nil)

        let statusItem = CPListItem(
            text: UPnPDevice.shared.friendlyName,
            detailText: "Receiver Active on :\(HTTPServer.shared.port)",
            image: UIImage(systemName: "antenna.radiowaves.left.and.right")
        )
        let sectionStatus = CPListSection(items: [statusItem], header: "DLNA Receiver Status", sectionIndexTitle: nil)

        let template = CPListTemplate(title: "Vimu", sections: [sectionMedia, sectionStatus])
        return template
    }
}
