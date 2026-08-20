import Foundation
import CarPlay
import OSLog

private let logger = Logger(subsystem: "com.kelvinsze.vimu", category: "CarPlayTemplateBuilder")

/// Builds CPListTemplates and action sheets for CarPlay UI.
@MainActor
public final class CarPlayTemplateBuilder {

    public static func buildRootTemplate(interfaceController: CPInterfaceController) -> CPListTemplate {
        let session = PlayerService.shared.session
        var sections: [CPListSection] = []

        // MARK: - 1. Now Playing Section
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
            sections.append(CPListSection(items: [nowPlayingItem], header: "正在播放", sectionIndexTitle: nil))
        }

        // MARK: - 2. Personal Media Servers Section (Emby / Jellyfin)
        let savedServers = MediaServerManager.shared.savedServers
        if !savedServers.isEmpty {
            let serverItems = savedServers.map { server in
                let item = CPListItem(
                    text: server.name,
                    detailText: server.serverType.uppercased() + " 媒体库",
                    image: UIImage(systemName: server.serverType == "emby" ? "tv.fill" : "play.square.stack.fill")
                )
                item.handler = { _, completion in
                    // Push server library list on CarPlay
                    pushServerLibraries(server: server, interfaceController: interfaceController)
                    completion()
                }
                return item
            }
            sections.append(CPListSection(items: serverItems, header: "个人媒体库 (Emby / Jellyfin)", sectionIndexTitle: nil))
        }

        // MARK: - 3. Test Streams Section
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
        sections.append(CPListSection(items: sampleItems, header: "内置测试源 (Q50L 实车验证)", sectionIndexTitle: nil))

        // MARK: - 4. Receiver Status Section
        let statusItem = CPListItem(
            text: UPnPDevice.shared.friendlyName,
            detailText: "DLNA 接收端已就绪 (端口 :\(HTTPServer.shared.port))",
            image: UIImage(systemName: "antenna.radiowaves.left.and.right")
        )
        statusItem.handler = { _, completion in
            completion()
        }
        sections.append(CPListSection(items: [statusItem], header: "投送接收器状态", sectionIndexTitle: nil))

        let template = CPListTemplate(title: "Vimu", sections: sections)
        return template
    }

    private static func pushServerLibraries(server: SavedServerInfo, interfaceController: CPInterfaceController) {
        guard let client = MediaServerManager.shared.getClient(for: server.id) else { return }

        Task {
            do {
                let libs = try await client.fetchLibraries()
                let items = libs.map { lib in
                    let item = CPListItem(
                        text: lib.name,
                        detailText: lib.collectionType?.capitalized ?? "媒体库",
                        image: UIImage(systemName: "folder.fill")
                    )
                    item.handler = { _, completion in
                        pushLibraryVideos(client: client, library: lib, interfaceController: interfaceController)
                        completion()
                    }
                    return item
                }

                await MainActor.run {
                    let template = CPListTemplate(title: server.name, sections: [CPListSection(items: items)])
                    interfaceController.pushTemplate(template, animated: true, completion: nil)
                }
            } catch {
                logger.error("Failed to fetch CarPlay libraries: \(error.localizedDescription)")
            }
        }
    }

    private static func pushLibraryVideos(client: MediaServerProtocol, library: MediaLibrary, interfaceController: CPInterfaceController) {
        Task {
            do {
                let videos = try await client.fetchItems(libraryId: library.id, startIndex: 0, limit: 30)
                let items = videos.map { video in
                    let item = CPListItem(
                        text: video.title,
                        detailText: video.duration != nil ? SOAPParser.formatUPnPTime(video.duration!) : "视频",
                        image: UIImage(systemName: "play.circle.fill")
                    )
                    item.handler = { _, completion in
                        PlayerService.shared.loadAndPlay(item: video)
                        completion()
                    }
                    return item
                }

                await MainActor.run {
                    let template = CPListTemplate(title: library.name, sections: [CPListSection(items: items)])
                    interfaceController.pushTemplate(template, animated: true, completion: nil)
                }
            } catch {
                logger.error("Failed to fetch CarPlay videos: \(error.localizedDescription)")
            }
        }
    }
}
