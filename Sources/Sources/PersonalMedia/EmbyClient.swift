import Foundation
import OSLog

private let logger = Logger(subsystem: "com.kelvinsze.vimu", category: "EmbyClient")

/// Emby Server API client conforming to MediaServerProtocol.
public final class EmbyClient: MediaServerProtocol, @unchecked Sendable {
    public let serverId: UUID
    public var serverName: String
    public var serverBaseURL: URL
    public private(set) var accessToken: String?
    public private(set) var userId: String?

    public var isAuthenticated: Bool {
        return accessToken != nil && !(accessToken?.isEmpty ?? true)
    }

    public var playbackRequestHeaders: [String: String]? { authorizationHeaders() }

    public init(
        id: UUID = UUID(),
        serverName: String,
        serverBaseURL: URL,
        accessToken: String? = nil,
        userId: String? = nil
    ) {
        self.serverId = id
        self.serverName = serverName
        self.serverBaseURL = serverBaseURL
        self.accessToken = accessToken
        self.userId = userId
    }

    // MARK: - Authentication

    public func authenticate(username: String, password: String) async throws -> String {
        let authURL = serverBaseURL.appendingPathComponent("Users/AuthenticateByName")
        var request = URLRequest(url: authURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let authHeader = "MediaBrowser Client=\"Emby for iOS\", Device=\"iPhone\", DeviceId=\"\(UPnPDevice.shared.uuid)\", Version=\"2.1.2\""
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue(authHeader, forHTTPHeaderField: "X-Emby-Authorization")
        request.setValue("Emby/2.1.2", forHTTPHeaderField: "X-Application")
        request.setValue("Emby/2.1.2 (com.emby.ios; build:38; iOS 18.0.0) Alamofire/5.9.1", forHTTPHeaderField: "User-Agent")

        let body: [String: String] = [
            "Username": username.trimmingCharacters(in: .whitespacesAndNewlines),
            "Pw": password
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw MediaServerError.authenticationFailed
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["AccessToken"] as? String,
              let userObj = json["User"] as? [String: Any],
              let uid = userObj["Id"] as? String else {
            throw MediaServerError.invalidResponse
        }

        self.accessToken = token
        self.userId = uid
        logger.info("Emby authenticated successfully for user: \(username)")
        return token
    }

    // MARK: - Media Libraries

    public func fetchLibraries() async throws -> [MediaLibrary] {
        guard let uid = userId else { throw MediaServerError.notAuthenticated }
        let url = serverBaseURL.appendingPathComponent("emby/Users/\(uid)/Views")
        let request = makeAuthorizedRequest(url: url)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw MediaServerError.requestFailed(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["Items"] as? [[String: Any]] else {
            return []
        }

        return items.compactMap { item -> MediaLibrary? in
            guard let id = item["Id"] as? String, let name = item["Name"] as? String else { return nil }
            let colType = item["CollectionType"] as? String
            return MediaLibrary(id: id, name: name, collectionType: colType)
        }
    }

    // MARK: - Items in Library

    public func fetchItems(libraryId: String, startIndex: Int = 0, limit: Int = 50) async throws -> [MediaItem] {
        guard let uid = userId else { throw MediaServerError.notAuthenticated }
        return try await fetchMappedItems(userID: uid, queryItems: [
            URLQueryItem(name: "ParentId", value: libraryId),
            URLQueryItem(name: "StartIndex", value: "\(startIndex)"),
            URLQueryItem(name: "Limit", value: "\(limit)"),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "IncludeItemTypes", value: "Movie,Episode,Video"),
            URLQueryItem(name: "Fields", value: "MediaSources,Overview,Path,MediaStreams")
        ])
    }

    public func fetchPlaybackStreamURL(itemId: String) async throws -> URL {
        (try await fetchPlaybackInfo(itemId: itemId)).url
    }

    public func search(query: String, limit: Int = 25) async throws -> [MediaItem] {
        guard let uid = userId else { throw MediaServerError.notAuthenticated }
        return try await fetchMappedItems(userID: uid, queryItems: [
            URLQueryItem(name: "SearchTerm", value: query), URLQueryItem(name: "Limit", value: "\(limit)"),
            URLQueryItem(name: "Recursive", value: "true"), URLQueryItem(name: "IncludeItemTypes", value: "Movie,Episode,Video"),
            URLQueryItem(name: "Fields", value: "MediaSources,Overview,Path,MediaStreams")
        ])
    }

    public func fetchContinueWatching(limit: Int = 25) async throws -> [MediaItem] {
        guard let uid = userId else { throw MediaServerError.notAuthenticated }
        return try await fetchMappedItems(userID: uid, queryItems: [
            URLQueryItem(name: "Limit", value: "\(limit)"), URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "Filters", value: "IsResumable"), URLQueryItem(name: "SortBy", value: "DatePlayed"),
            URLQueryItem(name: "SortOrder", value: "Descending"), URLQueryItem(name: "IncludeItemTypes", value: "Movie,Episode,Video"),
            URLQueryItem(name: "Fields", value: "MediaSources,Overview,Path,MediaStreams")
        ])
    }

    private func fetchMappedItems(userID: String, queryItems: [URLQueryItem]) async throws -> [MediaItem] {
        var components = URLComponents(url: serverBaseURL.appendingPathComponent("emby/Users/\(userID)/Items"), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems
        guard let url = components?.url else { throw MediaServerError.invalidURL }
        let (data, response) = try await URLSession.shared.data(for: makeAuthorizedRequest(url: url))
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw MediaServerError.requestFailed(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["Items"] as? [[String: Any]] else { return [] }
        return items.compactMap { makeMediaItem(from: $0) }
    }

    private func makeMediaItem(from dict: [String: Any]) -> MediaItem? {
        guard let id = dict["Id"] as? String, let name = dict["Name"] as? String else { return nil }
        let duration = ((dict["RunTimeTicks"] as? Double) ?? 0) / 10_000_000
        let playback = MediaPlaybackInfoSelector.select(itemId: id, baseURL: serverBaseURL, payload: dict, streamPath: "emby/Videos/\(id)/stream")
        return MediaItem(title: name, url: playback?.url ?? serverBaseURL.appendingPathComponent("emby/Videos/\(id)/stream.mp4"), sourceType: .personalMedia, mimeType: "video/mp4", duration: duration > 0 ? duration : nil, headers: authorizationHeaders(), originator: serverName, serverID: serverId, serverItemID: id, playSessionID: playback?.playSessionId, mediaSourceID: playback?.mediaSourceId, resumePosition: playback?.resumePosition ?? (((dict["UserData"] as? [String: Any])?["PlaybackPositionTicks"] as? Double ?? 0) / 10_000_000))
    }

    public func fetchPlaybackInfo(itemId: String) async throws -> MediaPlaybackInfo {
        guard let uid = userId else { throw MediaServerError.notAuthenticated }
        var components = URLComponents(url: serverBaseURL.appendingPathComponent("emby/Items/\(itemId)/PlaybackInfo"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "UserId", value: uid)]
        guard let url = components?.url else { throw MediaServerError.invalidURL }
        var request = makeAuthorizedRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "EnableDirectPlay": true,
            "EnableDirectStream": true,
            "EnableTranscoding": true,
            "IsPlayback": true
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let info = MediaPlaybackInfoSelector.select(itemId: itemId, baseURL: serverBaseURL, payload: json, streamPath: "emby/Videos/\(itemId)/stream") else {
            throw MediaServerError.invalidResponse
        }
        return info
    }

    public func reportPlaybackProgress(itemId: String, position: TimeInterval, isPaused: Bool, isStopped: Bool, playSessionId: String?, mediaSourceId: String?) async throws {
        let endpoint = isStopped ? "emby/Sessions/Playing/Stopped" : "emby/Sessions/Playing/Progress"
        let url = serverBaseURL.appendingPathComponent(endpoint)
        var request = makeAuthorizedRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let ticks = Int64(position * 10_000_000.0)
        let body: [String: Any] = [
            "ItemId": itemId,
            "PositionTicks": ticks,
            "IsPaused": isPaused,
            "EventName": isStopped ? "stopped" : "timeupdate"
        ]
        var mutableBody = body
        if let playSessionId { mutableBody["PlaySessionId"] = playSessionId }
        if let mediaSourceId { mutableBody["MediaSourceId"] = mediaSourceId }
        request.httpBody = try JSONSerialization.data(withJSONObject: mutableBody)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw MediaServerError.requestFailed(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500)
        }
    }

    // MARK: - Helpers

    private func makeAuthorizedRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        for (key, val) in authorizationHeaders() {
            request.setValue(val, forHTTPHeaderField: key)
        }
        return request
    }

    private func authorizationHeaders() -> [String: String] {
        let authHeader = "MediaBrowser Client=\"Emby for iOS\", Device=\"iPhone\", DeviceId=\"\(UPnPDevice.shared.uuid)\", Version=\"2.1.2\""
        var headers = [
            "Accept": "application/json",
            "Authorization": authHeader,
            "X-Emby-Authorization": authHeader,
            "X-Application": "Emby/2.1.2",
            "User-Agent": "Emby/2.1.2 (com.emby.ios; build:38; iOS 18.0.0) Alamofire/5.9.1"
        ]
        if let token = accessToken {
            headers["X-Emby-Token"] = token
        }
        return headers
    }
}
