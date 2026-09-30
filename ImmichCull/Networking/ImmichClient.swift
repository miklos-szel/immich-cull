import Foundation

/// Stateless client for the Immich REST API. All endpoints authenticate with the `x-api-key` header.
struct ImmichClient: Sendable {
    let serverURL: URL
    let apiKey: String
    private let session: URLSession

    /// Server search pages are fetched at this fixed size. It must not vary
    /// between pages: Immich turns `page` into an offset of `(page - 1) * size`,
    /// so shrinking the last request's size re-reads or skips items.
    private static let pageSize = 250

    /// `configuration` exists for unit tests, which install a stub `URLProtocol`.
    init(serverURL: URL, apiKey: String, configuration: URLSessionConfiguration = .default) {
        self.serverURL = serverURL
        self.apiKey = apiKey

        configuration.timeoutIntervalForRequest = 30
        session = URLSession(configuration: configuration)
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

    func tags() async throws -> [ImmichTag] {
        try await get("tags")
    }

    func searchAssets(page: Int, size: Int, order: String, albumIDs: [String]?, tagIDs: [String]?,
                      trashedAfter: String? = nil, withDeleted: Bool? = nil,
                      type: String? = nil, isNotInAlbum: Bool? = nil,
                      visibility: String? = nil, withExif: Bool = true) async throws -> SearchResult {
        let body = SearchRequest(albumIds: albumIDs, isNotInAlbum: isNotInAlbum, order: order,
                                 page: page, size: size, tagIds: tagIDs,
                                 trashedAfter: trashedAfter, type: type, visibility: visibility,
                                 withDeleted: withDeleted, withExif: withExif)
        return try await decode(send("POST", "search/metadata", body: body))
    }

    /// Everything currently in the Immich trash, as the user thinks of it: a
    /// Live Photo is one item, not a still plus its hidden motion movie.
    ///
    /// The motion part is dropped client-side rather than with
    /// `visibility: "timeline"`, which would also hide archived assets that
    /// were trashed — leaving them impossible to restore from the bin.
    func trashedAssets(limit: Int = 1000) async throws -> [ImmichAsset] {
        let assets = try await pagedSearch(limit: limit) { page in
            try await searchAssets(page: page, size: Self.pageSize, order: "desc", albumIDs: nil, tagIDs: nil,
                                   trashedAfter: "1970-01-01T00:00:00.000Z", withDeleted: true)
        }
        let motionParts = Set(assets.compactMap(\.livePhotoVideoId))
        return assets.filter { ($0.isTrashed ?? true) && !motionParts.contains($0.id) }
    }

    /// Pages through metadata search until exhausted or `limit` assets that
    /// satisfy `include` have been collected.
    ///
    /// `include` counts toward the limit, which is the point of it: filtering
    /// *after* a capped fetch means a library whose first `limit` assets are
    /// all excluded (e.g. already culled) never yields anything past them.
    func fetchAssets(albumIDs: [String]?, tagIDs: [String]?, order: String, limit: Int,
                     type: String? = nil, isNotInAlbum: Bool? = nil,
                     visibility: String? = nil, withExif: Bool = true,
                     include: @Sendable (ImmichAsset) -> Bool = { _ in true }) async throws -> [ImmichAsset] {
        try await pagedSearch(limit: limit, include: include) { page in
            try await searchAssets(page: page, size: Self.pageSize, order: order, albumIDs: albumIDs,
                                   tagIDs: tagIDs, type: type, isNotInAlbum: isNotInAlbum,
                                   visibility: visibility, withExif: withExif)
        }
    }

    /// IDs of every asset carrying any of the given tags (by full `value`, so a
    /// nested `Trips/culled` is not confused with a root `culled`). Used to
    /// badge photos that were already culled; unknown tags are skipped.
    func assetIDs(withAnyTagValue values: [String]) async throws -> Set<String> {
        guard !values.isEmpty else { return [] }
        let tagIDs = try await tags().filter { values.contains($0.value) }.map(\.id)
        return try await assetIDs(withAnyTagID: tagIDs)
    }

    /// Union of the assets carrying each tag. One request per tag, in parallel:
    /// Immich's AND/OR semantics for several `tagIds` aren't worth guessing at.
    /// EXIF is skipped because only the IDs are wanted and the result can be
    /// the whole library.
    func assetIDs(withAnyTagID tagIDs: [String]) async throws -> Set<String> {
        guard !tagIDs.isEmpty else { return [] }
        return try await withThrowingTaskGroup(of: [ImmichAsset].self) { group in
            for tagID in tagIDs {
                group.addTask {
                    try await fetchAssets(albumIDs: nil, tagIDs: [tagID], order: "desc", limit: .max,
                                          withExif: false)
                }
            }
            var result: Set<String> = []
            for try await assets in group { result.formUnion(assets.map(\.id)) }
            return result
        }
    }

    /// Shared paging loop: fixed page size, follow `nextPage`, trim to `limit`.
    private func pagedSearch(limit: Int, include: (ImmichAsset) -> Bool = { _ in true },
                             page fetch: (Int) async throws -> SearchResult) async throws -> [ImmichAsset] {
        var assets: [ImmichAsset] = []
        var page = 1
        while assets.count < limit {
            let result = try await fetch(page)
            assets += result.assets.items.lazy.filter(include).prefix(limit - assets.count)
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
        try await pagedSearch(limit: limit) { page in
            let body = SmartSearchRequest(query: query, page: page, size: 100)
            return try await decode(send("POST", "search/smart", body: body))
        }
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

    /// Creates the tag if needed and returns it. `value` is the tag's full path
    /// ("Trips/culled"); upserting a nested path can return its parents too, so
    /// the exact match is picked rather than the first element.
    func upsertTag(value: String) async throws -> ImmichTag {
        let tags: [ImmichTag] = try await decode(send("PUT", "tags", body: TagUpsertRequest(tags: [value])))
        guard let tag = tags.first(where: { $0.value == value }) ?? tags.last else { throw ImmichError.badResponse }
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

    /// Whether the server still has this asset. A permanently deleted asset
    /// answers 400 here, while one that merely lacks a generated preview
    /// answers 200 — which is the only reliable way to tell them apart.
    /// Network failures report `true` so a hiccup never discards a good asset.
    func assetExists(id: String) async -> Bool {
        var request = URLRequest(url: apiURL("assets/\(id)"))
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        guard let (_, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { return true }
        return (200..<300).contains(http.statusCode)
    }

    /// One asset by ID, or nil if the server no longer has it.
    func asset(id: String) async throws -> ImmichAsset? {
        do {
            return try await get("assets/\(id)")
        } catch ImmichError.http(let status, _) where status == 400 || status == 404 {
            return nil
        }
    }

    func originalURL(assetID: String) -> URL {
        apiURL("assets/\(assetID)/original")
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
        /// `true` restricts the search to assets in no album; omitted otherwise.
        let isNotInAlbum: Bool?
        let order: String
        let page: Int
        let size: Int
        let tagIds: [String]?
        let trashedAfter: String?
        /// "IMAGE" or "VIDEO"; omitted entirely when both are wanted.
        let type: String?
        /// "timeline" excludes hidden Live Photo motion parts and archived assets;
        /// omitted returns every visibility level (the server default).
        let visibility: String?
        let withDeleted: Bool?
        let withExif: Bool?
    }
    private struct SmartSearchRequest: Encodable {
        let query: String
        let page: Int
        let size: Int
    }
}
