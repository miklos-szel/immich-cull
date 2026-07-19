import Foundation

/// Stateless client for the Immich REST API. All endpoints authenticate with the `x-api-key` header.
struct ImmichClient: Sendable {
    let serverURL: URL
    let apiKey: String
    private let session: URLSession

    init(serverURL: URL, apiKey: String) {
        self.serverURL = serverURL
        self.apiKey = apiKey

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
    }

    // MARK: Endpoints

    /// Unauthenticated liveness probe; also used by discovery.
    static func ping(serverURL: URL, timeout: TimeInterval = 2) async -> Bool {
        var request = URLRequest(url: serverURL.appending(path: "api/server/ping"))
        request.timeoutInterval = timeout
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let pong = try? JSONDecoder().decode(PingResponse.self, from: data) else {
            return false
        }
        return pong.res == "pong"
    }

    func currentUser() async throws -> ImmichUser {
        try await get("users/me")
    }

    func albums() async throws -> [ImmichAlbum] {
        try await get("albums")
    }

    func searchAssets(page: Int, size: Int, order: String, albumIDs: [String]?, tagIDs: [String]?,
                      trashedAfter: String? = nil, withDeleted: Bool? = nil) async throws -> SearchResult {
        let body = SearchRequest(albumIds: albumIDs, order: order, page: page, size: size, tagIds: tagIDs,
                                 trashedAfter: trashedAfter, withDeleted: withDeleted, withExif: true)
        return try await decode(send("POST", "search/metadata", body: body))
    }

    /// Everything currently in the Immich trash.
    func trashedAssets(limit: Int = 1000) async throws -> [ImmichAsset] {
        var assets: [ImmichAsset] = []
        var page = 1
        while assets.count < limit {
            let size = min(250, limit - assets.count)
            let result = try await searchAssets(page: page, size: size, order: "desc", albumIDs: nil, tagIDs: nil,
                                                trashedAfter: "1970-01-01T00:00:00.000Z", withDeleted: true)
            assets += result.assets.items.prefix(limit - assets.count)
            guard assets.count < limit,
                  let next = result.assets.nextPage, let nextPage = Int(next) else { break }
            page = nextPage
        }
        return assets.filter { $0.isTrashed ?? true }
    }

    /// Pages through metadata search until exhausted or `limit` is reached.
    func fetchAssets(albumIDs: [String]?, tagIDs: [String]?, order: String, limit: Int) async throws -> [ImmichAsset] {
        var assets: [ImmichAsset] = []
        var page = 1
        while assets.count < limit {
            let size = min(250, limit - assets.count)
            let result = try await searchAssets(page: page, size: size, order: order, albumIDs: albumIDs, tagIDs: tagIDs)
            assets += result.assets.items.prefix(limit - assets.count)
            guard assets.count < limit,
                  let next = result.assets.nextPage, let nextPage = Int(next) else { break }
            page = nextPage
        }
        return assets
    }

    func duplicates() async throws -> [DuplicateGroup] {
        try await get("duplicates")
    }

    func trashStatistics() async throws -> AssetStats {
        let url = apiURL("assets/statistics").appending(queryItems: [URLQueryItem(name: "isTrashed", value: "true")])
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ImmichError.badResponse
        }
        return try decode(data)
    }

    /// CLIP-ranked smart search; returns up to `limit` best matches.
    func smartSearchAssets(query: String, limit: Int) async throws -> [ImmichAsset] {
        var assets: [ImmichAsset] = []
        var page = 1
        while assets.count < limit {
            let size = min(100, limit - assets.count)
            let body = SmartSearchRequest(query: query, page: page, size: size)
            let result: SearchResult = try await decode(send("POST", "search/smart", body: body))
            assets += result.assets.items
            guard let next = result.assets.nextPage, let nextPage = Int(next) else { break }
            page = nextPage
        }
        return assets
    }

    /// Moves assets to the trash (recoverable); `force` would delete permanently.
    func trashAssets(ids: [String]) async throws {
        _ = try await send("DELETE", "assets", body: TrashRequest(ids: ids, force: false))
    }

    /// Permanently deletes assets (bypasses the trash / removes from it).
    func permanentlyDeleteAssets(ids: [String]) async throws {
        _ = try await send("DELETE", "assets", body: TrashRequest(ids: ids, force: true))
    }

    func restoreAssets(ids: [String]) async throws {
        _ = try await send("POST", "trash/restore/assets", body: BulkIDs(ids: ids))
    }

    func setFavorite(ids: [String], isFavorite: Bool) async throws {
        _ = try await send("PUT", "assets", body: FavoriteRequest(ids: ids, isFavorite: isFavorite))
    }

    func addAssets(toAlbum albumID: String, ids: [String]) async throws {
        _ = try await send("PUT", "albums/\(albumID)/assets", body: BulkIDs(ids: ids))
    }

    func removeAssets(fromAlbum albumID: String, ids: [String]) async throws {
        _ = try await send("DELETE", "albums/\(albumID)/assets", body: BulkIDs(ids: ids))
    }

    /// Creates the tag if needed and returns it.
    func upsertTag(named name: String) async throws -> ImmichTag {
        let tags: [ImmichTag] = try await decode(send("PUT", "tags", body: TagUpsertRequest(tags: [name])))
        guard let tag = tags.first else { throw ImmichError.badResponse }
        return tag
    }

    func tagAssets(tagID: String, assetIDs: [String]) async throws {
        _ = try await send("PUT", "tags/assets", body: TagAssetsRequest(assetIds: assetIDs, tagIds: [tagID]))
    }

    func untagAssets(tagID: String, assetIDs: [String]) async throws {
        _ = try await send("DELETE", "tags/\(tagID)/assets", body: BulkIDs(ids: assetIDs))
    }

    // MARK: Media URLs

    func thumbnailURL(assetID: String, size: String = "preview") -> URL {
        apiURL("assets/\(assetID)/thumbnail").appending(queryItems: [URLQueryItem(name: "size", value: size)])
    }

    func videoPlaybackURL(assetID: String) -> URL {
        apiURL("assets/\(assetID)/video/playback")
    }

    // MARK: Plumbing

    private func apiURL(_ path: String) -> URL {
        serverURL.appending(path: "api").appending(path: path)
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try await decode(send("GET", path, body: nil as BulkIDs?))
    }

    private func send(_ method: String, _ path: String, body: (some Encodable)?) async throws -> Data {
        var request = URLRequest(url: apiURL(path))
        request.httpMethod = method
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ImmichError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.message
            throw ImmichError.http(status: http.statusCode, message: message)
        }
        return data
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ImmichError.badResponse
        }
    }

    // MARK: Request/response DTOs

    private struct PingResponse: Decodable { let res: String }
    private struct ErrorResponse: Decodable { let message: String? }
    private struct BulkIDs: Encodable { let ids: [String] }
    private struct TrashRequest: Encodable {
        let ids: [String]
        let force: Bool
    }
    private struct TagUpsertRequest: Encodable { let tags: [String] }
    private struct FavoriteRequest: Encodable {
        let ids: [String]
        let isFavorite: Bool
    }
    private struct TagAssetsRequest: Encodable {
        let assetIds: [String]
        let tagIds: [String]
    }
    private struct SearchRequest: Encodable {
        let albumIds: [String]?
        let order: String
        let page: Int
        let size: Int
        let tagIds: [String]?
        let trashedAfter: String?
        let withDeleted: Bool?
        let withExif: Bool?
    }
    private struct SmartSearchRequest: Encodable {
        let query: String
        let page: Int
        let size: Int
    }
}
