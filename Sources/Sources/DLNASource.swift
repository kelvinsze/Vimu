import Foundation

/// DLNA Cast source wrapper.
public struct DLNASource {
    public static func createMediaItem(uri: URL, metadata: String?) -> MediaItem {
        let title: String
        if let metadata = metadata, let extracted = SOAPParser.extractTitleFromDIDLLite(metadata), !extracted.isEmpty {
            title = extracted
        } else {
            title = uri.lastPathComponent.isEmpty ? "DLNA Stream" : uri.lastPathComponent
        }

        return MediaItem(
            title: title,
            url: uri,
            sourceType: .dlna,
            originator: "DLNA Cast"
        )
    }
}
