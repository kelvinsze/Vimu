import Foundation
import CarPlay
import OSLog

private let logger = Logger(subsystem: "com.kelvinsze.vimu", category: "CarPlayTemplateBuilder")

/// Builds CPListTemplates and action sheets for CarPlay UI.
@MainActor
public final class CarPlayTemplateBuilder {

    public static func buildRootTemplate(interfaceController: CPInterfaceController) -> CPListTemplate {
        let session = PlayerService.shared.session
        var mediaItems: [CPListItem] = []

        // Now Playing / Active Session Item
        if let current = session.currentItem {
            let isPlaying = session.status == .playing
            let nowPlayingItem = CPListItem(
                text: current.title,
                detailText: "\(isPlaying ? "▶ 正在播放" : "⏸ 已暂停") · \(SOAPParser.formatUPnPTime(session.currentTime)) / \(SOAPParser.formatUPnPTime(session.duration))",
                image: UIImage(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
            )
            nowPlayingItem.handler = { _, completion in
                PlayerService.shared.togglePlayPause()
                completion()
            }
            mediaItems.append(nowPlayingItem)
        }

        // Test Streams for Q50L Gate 1 validation
        let sampleItems = MediaItem.sampleStreams.map { sample in
            let item = CPListItem(
                text: sample.title,
                detailText: sample.mimeType?.contains("mpegURL") == true ? "HLS 视频流" : "MP4 视频",
                image: UIImage(systemName: "film.fill")
            )
            item.handler = { _, completion in
                PlayerService.shared.loadAndPlay(item: sample)
                completion()
            }
            return item
        }
        mediaItems.append(contentsOf: sampleItems)

        let sectionMedia = CPListSection(items: mediaItems, header: "媒体与测试源", sectionIndexTitle: nil)

        // Receiver Status Section
        let statusItem = CPListItem(
            text: UPnPDevice.shared.friendlyName,
            detailText: "DLNA 接收端已就绪 (端口 :\(HTTPServer.shared.port))",
            image: UIImage(systemName: "antenna.radiowaves.left.and.right")
        )
        statusItem.handler = { _, completion in
            completion()
        }

        let sectionStatus = CPListSection(items: [statusItem], header: "投送接收器状态", sectionIndexTitle: nil)

        let template = CPListTemplate(title: "Vimu", sections: [sectionMedia, sectionStatus])
        return template
    }
}
