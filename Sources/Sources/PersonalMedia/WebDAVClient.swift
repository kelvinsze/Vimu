import Foundation

/// A read-only WebDAV media source. It intentionally uses the standard DAV
/// methods rather than a server-specific API, so it also covers fnOS WebDAV.
public final class WebDAVClient: MediaServerProtocol, @unchecked Sendable {
    public let serverId: UUID
    public let serverName: String
    public let serverBaseURL: URL
    private let username: String
    private var password: String?

    public var isAuthenticated: Bool { password != nil }
    public var playbackRequestHeaders: [String: String]? { authorizationHeaders }

    public init(id: UUID = UUID(), serverName: String, serverBaseURL: URL, username: String, password: String? = nil) {
        self.serverId = id
        self.serverName = serverName
        self.serverBaseURL = serverBaseURL
        self.username = username
        self.password = password
    }

    public func authenticate(username: String, password: String) async throws -> String {
        self.password = password
        var request = makeRequest(url: serverBaseURL)
        request.httpMethod = "PROPFIND"
        request.setValue("0", forHTTPHeaderField: "Depth")
        request.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("""
        <?xml version="1.0" encoding="utf-8" ?>
        <propfind xmlns="DAV:"><prop><resourcetype/></prop></propfind>
        """.utf8)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MediaServerError.invalidResponse }
        guard (200..<300).contains(http.statusCode) || http.statusCode == 207 else {
            throw MediaServerError.requestFailed(statusCode: http.statusCode)
        }
        return password
    }

    public func fetchLibraries() async throws -> [MediaLibrary] {
        guard isAuthenticated else { throw MediaServerError.notAuthenticated }
        return [MediaLibrary(id: "root", name: serverName, collectionType: "videos")]
    }

    public func fetchItems(libraryId: String, startIndex: Int, limit: Int) async throws -> [MediaItem] {
        let files = try await scanVideoFiles(maximumCount: max(startIndex + limit, 100))
        return Array(files.dropFirst(startIndex).prefix(limit))
    }

    public func fetchPlaybackInfo(itemId: String) async throws -> MediaPlaybackInfo {
        guard let url = URL(string: itemId, relativeTo: serverBaseURL)?.absoluteURL else { throw MediaServerError.invalidURL }
        return MediaPlaybackInfo(itemId: itemId, url: url, method: .directPlay)
    }

    public func fetchPlaybackStreamURL(itemId: String) async throws -> URL {
        try await fetchPlaybackInfo(itemId: itemId).url
    }

    public func search(query: String, limit: Int) async throws -> [MediaItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        return try await scanVideoFiles(maximumCount: 400)
            .filter { $0.title.localizedCaseInsensitiveContains(needle) }
            .prefix(limit)
            .map { $0 }
    }

    public func fetchContinueWatching(limit: Int) async throws -> [MediaItem] { [] }

    public func reportPlaybackProgress(itemId: String, position: TimeInterval, isPaused: Bool, isStopped: Bool, playSessionId: String?, mediaSourceId: String?) async throws {
        // Standard WebDAV has no playback-history endpoint.
    }

    private var authorizationHeaders: [String: String]? {
        guard let password else { return nil }
        let credential = Data("\(username):\(password)".utf8).base64EncodedString()
        return ["Authorization": "Basic \(credential)"]
    }

    private func makeRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        authorizationHeaders?.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        return request
    }

    private func scanVideoFiles(maximumCount: Int) async throws -> [MediaItem] {
        guard isAuthenticated else { throw MediaServerError.notAuthenticated }
        var pending = [serverBaseURL]
        var visited = Set<String>()
        var results: [MediaItem] = []

        while let directory = pending.popLast(), results.count < maximumCount, visited.count < 256 {
            let canonical = directory.absoluteString
            guard visited.insert(canonical).inserted else { continue }
            for entry in try await list(directory: directory) where entry.url != directory {
                if entry.isDirectory {
                    pending.append(entry.url)
                } else if Self.playableExtensions.contains(entry.url.pathExtension.lowercased()) {
                    results.append(MediaItem(
                        title: entry.displayName,
                        url: entry.url,
                        sourceType: .personalMedia,
                        mimeType: Self.mimeType(for: entry.url),
                        headers: authorizationHeaders,
                        originator: serverName,
                        serverID: serverId,
                        serverItemID: entry.url.absoluteString,
                        containerHint: entry.url.pathExtension.lowercased()
                    ))
                    if results.count == maximumCount { break }
                }
            }
        }
        return results.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private func list(directory: URL) async throws -> [WebDAVEntry] {
        var request = makeRequest(url: directory)
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("""
        <?xml version="1.0" encoding="utf-8" ?>
        <propfind xmlns="DAV:"><prop><displayname/><resourcetype/></prop></propfind>
        """.utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MediaServerError.invalidResponse }
        guard http.statusCode == 207 else { throw MediaServerError.requestFailed(statusCode: http.statusCode) }
        return try WebDAVResponseParser.parse(data: data, baseURL: serverBaseURL)
    }

    private static let playableExtensions: Set<String> = ["m3u8", "mp4", "m4v", "mov", "mkv", "webm", "avi", "ts", "m2ts", "mpg", "mpeg", "mpd"]

    private static func mimeType(for url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "m3u8": return "application/x-mpegURL"
        case "mp4", "m4v": return "video/mp4"
        case "mov": return "video/quicktime"
        case "mkv": return "video/x-matroska"
        case "webm": return "video/webm"
        default: return nil
        }
    }
}

private struct WebDAVEntry: Equatable {
    let url: URL
    let displayName: String
    let isDirectory: Bool
}

private enum WebDAVResponseParser {
    static func parse(data: Data, baseURL: URL) throws -> [WebDAVEntry] {
        let parser = XMLParser(data: data)
        let delegate = Delegate(baseURL: baseURL)
        parser.delegate = delegate
        guard parser.parse() else { throw MediaServerError.invalidResponse }
        return delegate.entries
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        let baseURL: URL
        var entries: [WebDAVEntry] = []
        private var href: String?
        private var displayName: String?
        private var isDirectory = false
        private var text = ""
        private var currentElement = ""

        init(baseURL: URL) { self.baseURL = baseURL }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String : String] = [:]) {
            let name = qName ?? elementName
            currentElement = name.split(separator: ":").last.map(String.init) ?? name
            if currentElement == "response" { href = nil; displayName = nil; isDirectory = false }
            if currentElement == "collection" { isDirectory = true }
            text = ""
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            let name = (qName ?? elementName).split(separator: ":").last.map(String.init) ?? elementName
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if name == "href" { href = value }
            if name == "displayname" { displayName = value }
            if name == "response", let href, let url = URL(string: href, relativeTo: baseURL)?.absoluteURL {
                let fallback = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
                entries.append(WebDAVEntry(url: url, displayName: displayName?.isEmpty == false ? displayName! : fallback, isDirectory: isDirectory))
            }
            text = ""
            currentElement = ""
        }
    }
}
