import Foundation

/// An in-memory Immich for unit tests, served through `MockImmichProtocol`.
///
/// It models only what the shared layer depends on, but models it the way the
/// real server behaves where that has bitten before: pages are offsets of
/// `(page - 1) * size`, upserting a nested tag also returns its parents, and a
/// Live Photo's motion part is its own (trashable) asset.
final class MockImmich: @unchecked Sendable {
    struct Asset {
        var id: String
        var type = "IMAGE"
        var fileName: String
        var localDateTime = "2026-06-10T12:00:00.000Z"
        var isFavorite = false
        var isTrashed = false
        var livePhotoVideoId: String?
    }

    struct Request {
        let method: String
        let path: String
        let body: [String: Any]
    }

    nonisolated(unsafe) static var current = MockImmich()

    private let lock = NSLock()
    private var _assets: [Asset] = []
    private var _albums: [String: (name: String, members: Set<String>)] = [:]
    private var _tags: [String: String] = [:]          // value -> id
    private var _tagged: [String: Set<String>] = [:]   // tag id -> asset ids
    private var _log: [Request] = []
    private var _failTrash = false

    static let baseURL = URL(string: "https://mock.immich.test")!

    /// A client whose every request lands on `MockImmich.current`.
    static func client() -> ImmichClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockImmichProtocol.self]
        return ImmichClient(serverURL: baseURL, apiKey: "test-key", configuration: configuration)
    }

    // MARK: Fixture setup

    @discardableResult
    func addAssets(_ count: Int, prefix: String = "a") -> [String] {
        (0..<count).map { index in
            let id = "\(prefix)\(index)"
            // Distinct, descending-sortable dates so order is well defined.
            let date = String(format: "2026-06-%02dT%02d:00:00.000Z", 1 + index / 24, index % 24)
            add(Asset(id: id, fileName: "IMG_\(id).jpg", localDateTime: date))
            return id
        }
    }

    func add(_ asset: Asset) {
        lock.withLock { _assets.append(asset) }
    }

    func addAlbum(id: String, name: String, members: [String] = []) {
        lock.withLock { _albums[id] = (name, Set(members)) }
    }

    @discardableResult
    func addTag(_ value: String, on assetIDs: [String] = []) -> String {
        lock.withLock {
            // A nested tag always has its parents on a real server.
            let segments = value.split(separator: "/")
            for depth in 1..<segments.count {
                _ = upsertTagLocked(segments.prefix(depth).joined(separator: "/"))
            }
            let id = upsertTagLocked(value)
            _tagged[id, default: []].formUnion(assetIDs)
            return id
        }
    }

    var failTrash: Bool {
        get { lock.withLock { _failTrash } }
        set { lock.withLock { _failTrash = newValue } }
    }

    // MARK: Inspection

    var log: [Request] { lock.withLock { _log } }
    func requests(_ method: String, _ path: String) -> [Request] {
        log.filter { $0.method == method && $0.path == path }
    }
    func asset(_ id: String) -> Asset? { lock.withLock { _assets.first { $0.id == id } } }
    func tagID(_ value: String) -> String? { lock.withLock { _tags[value] } }
    var tagValues: Set<String> { lock.withLock { Set(_tags.keys) } }
    func isTagged(_ assetID: String, with value: String) -> Bool {
        lock.withLock { _tags[value].map { _tagged[$0, default: []].contains(assetID) } ?? false }
    }
    func members(of albumID: String) -> Set<String> { lock.withLock { _albums[albumID]?.members ?? [] } }

    // MARK: Routing

    func handle(method: String, path: String, body: [String: Any]) -> (Int, Any) {
        lock.withLock {
            _log.append(Request(method: method, path: path, body: body))
            let parts = path.split(separator: "/").map(String.init)   // ["api", ...]
            let ids = body["ids"] as? [String] ?? []

            switch (method, Array(parts.dropFirst())) {
            case ("GET", ["tags"]):
                return (200, _tags.map { tagJSON(id: $0.value, value: $0.key) })
            case ("PUT", ["tags"]):
                let values = body["tags"] as? [String] ?? []
                var result: [[String: Any]] = []
                for value in values {
                    // Like Immich: parents are upserted and returned too.
                    let segments = value.split(separator: "/")
                    for depth in 1...segments.count {
                        let partial = segments.prefix(depth).joined(separator: "/")
                        result.append(tagJSON(id: upsertTagLocked(partial), value: partial))
                    }
                }
                return (200, result)
            case ("PUT", ["tags", "assets"]):
                for tagID in body["tagIds"] as? [String] ?? [] {
                    _tagged[tagID, default: []].formUnion(body["assetIds"] as? [String] ?? [])
                }
                return (200, [[String: Any]]())
            case ("DELETE", let p) where p.count == 3 && p[0] == "tags" && p[2] == "assets":
                _tagged[p[1], default: []].subtract(ids)
                return (200, [[String: Any]]())
            case ("GET", ["albums"]):
                return (200, _albums.map { ["id": $0.key, "albumName": $0.value.name,
                                            "assetCount": $0.value.members.count] })
            case ("PUT", let p) where p.count == 3 && p[0] == "albums":
                _albums[p[1]]?.members.formUnion(ids)
                return (200, [[String: Any]]())
            case ("DELETE", let p) where p.count == 3 && p[0] == "albums":
                _albums[p[1]]?.members.subtract(ids)
                return (200, [[String: Any]]())
            case ("DELETE", ["assets"]):
                if _failTrash { return (500, ["message": "trash failed"]) }
                if body["force"] as? Bool == true {
                    _assets.removeAll { ids.contains($0.id) }
                } else {
                    for index in _assets.indices where ids.contains(_assets[index].id) {
                        _assets[index].isTrashed = true
                    }
                }
                return (204, [String: Any]())
            case ("POST", ["trash", "restore", "assets"]):
                for index in _assets.indices where ids.contains(_assets[index].id) {
                    _assets[index].isTrashed = false
                }
                return (200, [String: Any]())
            case ("PUT", ["assets"]):
                let favorite = body["isFavorite"] as? Bool ?? false
                for index in _assets.indices where ids.contains(_assets[index].id) {
                    _assets[index].isFavorite = favorite
                }
                return (204, [String: Any]())
            case ("GET", let p) where p.count == 2 && p[0] == "assets":
                guard let asset = _assets.first(where: { $0.id == p[1] }) else {
                    return (400, ["message": "Not found or no asset.read access"])
                }
                return (200, assetJSON(asset))
            case ("POST", ["search", "metadata"]):
                return (200, search(body))
            default:
                return (404, ["message": "unhandled \(method) \(path)"])
            }
        }
    }

    private func search(_ body: [String: Any]) -> [String: Any] {
        let trashed = body["withDeleted"] as? Bool == true && body["trashedAfter"] != nil
        var items = _assets.filter { $0.isTrashed == trashed }
        if let albumIDs = body["albumIds"] as? [String] {
            let allowed = albumIDs.reduce(into: Set<String>()) { $0.formUnion(_albums[$1]?.members ?? []) }
            items = items.filter { allowed.contains($0.id) }
        }
        if let tagIDs = body["tagIds"] as? [String] {
            let allowed = tagIDs.reduce(into: Set<String>()) { $0.formUnion(_tagged[$1] ?? []) }
            items = items.filter { allowed.contains($0.id) }
        }
        let descending = (body["order"] as? String ?? "desc") == "desc"
        items.sort { descending ? $0.localDateTime > $1.localDateTime : $0.localDateTime < $1.localDateTime }
        let page = body["page"] as? Int ?? 1
        let size = body["size"] as? Int ?? 250
        let start = min((page - 1) * size, items.count)
        let slice = items[start..<min(start + size, items.count)]
        let next: Any = start + size < items.count ? String(page + 1) : NSNull()
        return ["assets": ["items": slice.map(assetJSON), "nextPage": next]]
    }

    private func upsertTagLocked(_ value: String) -> String {
        if let id = _tags[value] { return id }
        let id = "tag-\(value)"
        _tags[value] = id
        return id
    }

    private func tagJSON(id: String, value: String) -> [String: Any] {
        ["id": id, "name": String(value.split(separator: "/").last ?? ""), "value": value]
    }

    private func assetJSON(_ asset: Asset) -> [String: Any] {
        var json: [String: Any] = [
            "id": asset.id, "type": asset.type, "originalFileName": asset.fileName,
            "localDateTime": asset.localDateTime, "isFavorite": asset.isFavorite,
            "isTrashed": asset.isTrashed,
        ]
        if let live = asset.livePhotoVideoId { json["livePhotoVideoId"] = live }
        return json
    }
}

/// Routes every request of a session configured by `MockImmich.client()` to
/// `MockImmich.current`.
final class MockImmichProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url else { return }
        let (status, json) = MockImmich.current.handle(method: request.httpMethod ?? "GET",
                                                       path: url.path(), body: bodyJSON())
        let data = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    /// URLSession hands a protocol the body as a stream, not `httpBody`.
    private func bodyJSON() -> [String: Any] {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                guard read > 0 else { break }
                data.append(buffer, count: read)
            }
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }
}
