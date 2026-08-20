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
        let authURL = serverBaseURL.appendingPathComponent("emby/Users/AuthenticateByName")
        var request = URLRequest(url: authURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let authHeader = "MediaBrowser Client=\"Vimu\", Device=\"iPhone\", DeviceId=\"\(UPnPDevice.shared.uuid)\", Version=\"0.1.0\""
        request.setValue(authHeader, forHTTPHeaderField: "X-Emby-Authorization")

        let body: [String: String] = ["Username": username, "Pw": password]
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
        var components = URLComponents(url: serverBaseURL.appendingPathComponent("emby/Users/\(uid)/Items"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "ParentId", value: libraryId),
            URLQueryItem(name: "StartIndex", value: "\(startIndex)"),
            URLQueryItem(name: "Limit", value: "\(limit)"),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "IncludeItemTypes", value: "Movie,Episode,Video"),
            URLQueryItem(name: "Fields", value: "MediaSources,Overview,Path,MediaStreams")
        ]

        guard let url = components?.url else { throw MediaServerError.invalidURL }
        let request = makeAuthorizedRequest(url: url)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw MediaServerError.requestFailed(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["Items"] as? [[String: Any]] else {
            return []
        }

        return items.compactMap { dict -> MediaItem? in
            guard let id = dict["Id"] as? String, let name = dict["Name"] as? String else { return nil }
            let durationTicks = (dict["RunTimeTicks"] as? Double) ?? 0
            let durationSeconds = durationTicks / 10_000_000.0

            let streamURL = self.serverBaseURL.appendingPathComponent("emby/Videos/\(id)/stream.mp4")

            var posterURL: URL?
            if let imageTags = dict["ImageTags"] as? [String: Any], imageTags["Primary"] != nil {
                posterURL = self.serverBaseURL.appendingPathComponent("emby/Items/\(id)/Images/Primary")
            }

            return MediaItem(
                title: name,
                url: streamURL,
                sourceType: .personalMedia,
                mimeType: "video/mp4",
                duration: durationSeconds > 0 ? durationSeconds : nil,
                posterUrl: posterURL,
                headers: self.authorizationHeaders(),
                originator: self.serverName
            )
        }
    }

    public func fetchPlaybackStreamURL(itemId: String) async throws -> URL {
        let url = serverBaseURL.appendingPathComponent("emby/Videos/\(itemId)/stream.mp4")
        return url
    }

    public func reportPlaybackProgress(itemId: String, position: TimeInterval, isPaused: Bool) async throws {
        let endpoint = isPaused ? "emby/Sessions/Playing/Progress" : "emby/Sessions/Playing/Progress"
        let url = serverBaseURL.appendingPathComponent(endpoint)
        var request = makeAuthorizedRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let ticks = Int64(position * 10_000_000.0)
        let body: [String: Any] = [
            "ItemId": itemId,
            "PositionTicks": ticks,
            "IsPaused": isPaused,
            "EventName": "timeupdate"
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: request)
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
        var headers = [
            "X-Emby-Authorization": "MediaBrowser Client=\"Vimu\", Device=\"iPhone\", DeviceId=\"\(UPnPDevice.shared.uuid)\", Version=\"0.1.0\""
        ]
        if let token = accessToken {
            headers["X-Emby-Token"] = token
        }
        return headers
    }
}
