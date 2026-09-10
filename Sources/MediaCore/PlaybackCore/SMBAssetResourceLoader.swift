import AVFoundation
import Foundation
import SMBClient
import UniformTypeIdentifiers

/// Supplies AVPlayer with byte ranges from an SMB2 share. The asset URL is an
/// opaque `mivu-smb://` URL, so SMB credentials never escape into a URL.
final class SMBAssetResourceLoader: NSObject, AVAssetResourceLoaderDelegate {
    private let reader: SMBRangeReader
    private let originalURL: URL
    let queue = DispatchQueue(label: "com.kold.mivu.smb-resource-loader")

    init?(url: URL) {
        guard let configuration = SMBPlaybackRegistry.shared.configuration(for: url),
              let remotePath = SMBPlaybackRegistry.shared.remotePath(for: url),
              !remotePath.isEmpty,
              configuration.password != nil else { return nil }
        self.reader = SMBRangeReader(configuration: configuration, remotePath: remotePath)
        self.originalURL = url
    }

    func makeAsset() -> AVURLAsset {
        let asset = AVURLAsset(url: originalURL)
        asset.resourceLoader.setDelegate(self, queue: queue)
        return asset
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        Task { [reader] in
            do {
                let metadata = try await reader.metadata()
                if let content = loadingRequest.contentInformationRequest {
                    content.contentLength = Int64(metadata.length)
                    content.contentType = metadata.contentType
                    content.isByteRangeAccessSupported = true
                }
                if let dataRequest = loadingRequest.dataRequest {
                    var offset = UInt64(max(dataRequest.currentOffset, dataRequest.requestedOffset))
                    var remaining = dataRequest.requestedLength
                    while remaining > 0, offset < metadata.length {
                        let count = min(remaining, 512 * 1024)
                        let chunk = try await reader.read(offset: offset, length: UInt32(count))
                        guard !chunk.isEmpty else { break }
                        dataRequest.respond(with: chunk)
                        offset += UInt64(chunk.count)
                        remaining -= chunk.count
                    }
                }
                loadingRequest.finishLoading()
            } catch {
                loadingRequest.finishLoading(with: error)
            }
        }
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        // Each request is bounded to 512 KiB chunks. The next AVFoundation
        // request naturally starts from its own byte offset after cancellation.
    }
}

/// Shared SMB range reader used by both AVFoundation and the loopback HTTP
/// adapter that feeds MPV. Credentials remain in `SMBPlaybackConfiguration`.
actor SMBRangeReader {
    struct Metadata: Sendable {
        let length: UInt64
        let contentType: String
    }

    private let configuration: SMBPlaybackConfiguration
    private let remotePath: String
    private var client: SMBClient?
    private var fileReader: FileReader?
    private var cachedMetadata: Metadata?

    init(configuration: SMBPlaybackConfiguration, remotePath: String) {
        self.configuration = configuration
        self.remotePath = remotePath
    }

    deinit {
        client?.session.disconnect()
    }

    func metadata() async throws -> Metadata {
        if let cachedMetadata { return cachedMetadata }
        let fileReader = try await openReader()
        let length = try await fileReader.fileSize
        let extensionName = URL(fileURLWithPath: remotePath).pathExtension
        let contentType = UTType(filenameExtension: extensionName)?.identifier ?? "public.data"
        let metadata = Metadata(length: length, contentType: contentType)
        cachedMetadata = metadata
        return metadata
    }

    func read(offset: UInt64, length: UInt32) async throws -> Data {
        let fileReader = try await openReader()
        return try await fileReader.read(offset: offset, length: length)
    }

    private func openReader() async throws -> FileReader {
        if let fileReader { return fileReader }
        guard let password = configuration.password else { throw MediaServerError.notAuthenticated }
        let client = SMBClient(host: configuration.host, port: configuration.port)
        try await client.login(username: configuration.username, password: password)
        try await client.connectShare(configuration.share)
        let reader = client.fileReader(path: remotePath)
        self.client = client
        self.fileReader = reader
        return reader
    }
}
