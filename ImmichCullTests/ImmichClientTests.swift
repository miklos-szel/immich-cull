import XCTest

/// Paging and listing rules in `ImmichClient`, against `MockImmich`.
final class ImmichClientTests: XCTestCase {
    private var server: MockImmich { MockImmich.current }

    override func setUp() async throws {
        MockImmich.current = MockImmich()
    }

    /// A shrinking last page used to be requested as `size: 50, page: 2`, which
    /// Immich reads as offset 50 — re-reading items already fetched.
    func testPagingKeepsAConstantPageSize() async throws {
        server.addAssets(600)
        let assets = try await MockImmich.client().fetchAssets(albumIDs: nil, tagIDs: nil,
                                                               order: "desc", limit: 300)

        XCTAssertEqual(assets.count, 300)
        XCTAssertEqual(Set(assets.map(\.id)).count, 300, "duplicates mean overlapping pages")
        let sizes = server.requests("POST", "/api/search/metadata").compactMap { $0.body["size"] as? Int }
        XCTAssertEqual(Set(sizes), [250])
    }

    /// Excluded assets must not use up the limit, or a library whose first
    /// `limit` assets are all culled never offers anything past them.
    func testExcludedAssetsDoNotCountTowardTheLimit() async throws {
        server.addAssets(10)   // a9 is newest
        let excluded: Set<String> = ["a9", "a8", "a7"]
        let assets = try await MockImmich.client().fetchAssets(albumIDs: nil, tagIDs: nil, order: "desc",
                                                               limit: 3) { !excluded.contains($0.id) }

        XCTAssertEqual(assets.map(\.id), ["a6", "a5", "a4"])
    }

    func testTrashListingShowsALivePhotoAsOneItem() async throws {
        server.add(.init(id: "still", fileName: "IMG_1.HEIC", isTrashed: true, livePhotoVideoId: "motion"))
        server.add(.init(id: "motion", type: "VIDEO", fileName: "IMG_1.MOV", isTrashed: true))
        server.add(.init(id: "clip", type: "VIDEO", fileName: "MOV_2.MOV", isTrashed: true))

        let trashed = try await MockImmich.client().trashedAssets()

        XCTAssertEqual(Set(trashed.map(\.id)), ["still", "clip"])
    }

    func testUpsertingANestedTagReturnsTheTagItself() async throws {
        let tag = try await MockImmich.client().upsertTag(value: "Trips/culled")

        XCTAssertEqual(tag.value, "Trips/culled", "the parent comes back first and must not be picked")
    }

    func testMissingAssetReadsAsNil() async throws {
        let asset = try await MockImmich.client().asset(id: "gone")
        XCTAssertNil(asset)
    }
}
