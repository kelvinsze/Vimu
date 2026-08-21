import Foundation
import OSLog

private let logger = Logger(subsystem: "com.kelvinsze.vimu", category: "PlaybackHistory")

/// Manages locally persisted playback history.
@MainActor
public final class PlaybackHistory: ObservableObject {
    public static let shared = PlaybackHistory()

    private let userDefaultsKey = "vimu_playback_history_v1"
    private let maxHistoryEntries = 50

    @Published public private(set) var items: [MediaItem] = []

    public init() {
        loadHistory()
    }

    public func addOrUpdate(item: MediaItem) {
        // Remove existing item with identical URL
        let safeItem = item.withoutSensitiveHeaders()
        items.removeAll { $0.url == safeItem.url }
        // Insert most recent at the top
        items.insert(safeItem, at: 0)

        if items.count > maxHistoryEntries {
            items = Array(items.prefix(maxHistoryEntries))
        }
        saveHistory()
    }

    public func remove(item: MediaItem) {
        items.removeAll { $0.id == item.id }
        saveHistory()
    }

    public func clear() {
        items.removeAll()
        saveHistory()
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else { return }
        do {
            items = try JSONDecoder().decode([MediaItem].self, from: data).map { $0.withoutSensitiveHeaders() }
            // Remove legacy Authorization/Cookie fields from the persisted history.
            saveHistory()
        } catch {
            logger.error("Failed to decode playback history: \(error.localizedDescription)")
        }
    }

    private func saveHistory() {
        do {
            let data = try JSONEncoder().encode(items)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } catch {
            logger.error("Failed to encode playback history: \(error.localizedDescription)")
        }
    }
}
