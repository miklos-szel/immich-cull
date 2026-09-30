import XCTest

/// `CullSession` against `MockImmich`. Each test pins down one way the
/// session's local bookkeeping and the server have drifted apart before.
///
/// Counters are asserted exactly. The lifetime `StatsStore` persists across
/// runs, so it is asserted as a *delta* from a snapshot.
@MainActor
final class CullSessionTests: XCTestCase {
    private var server: MockImmich { MockImmich.current }

    override func setUp() async throws {
        MockImmich.current = MockImmich()
    }

    // MARK: Counters and stats

    func testSkipBackThenSkipAgainCountsThePhotoOnce() async {
        server.addAssets(3)
        let stats = StatsStore()
        let before = snapshot(stats)
        let session = makeSession(stats: stats)
        await session.start()

        session.skipCurrent()
        session.goToPreviousImage()
        session.skipCurrent()
        await session.close()

        XCTAssertEqual(session.reviewedCount, 1)
        XCTAssertEqual(session.skippedCount, 1)
        XCTAssertEqual(snapshot(stats) - before, CullCounters(skipped: 1))
    }

    func testRemovingAPreexistingAlbumMemberThenUndoingLeavesNoCount() async {
        let ids = server.addAssets(3)
        server.addAlbum(id: "dest", name: "Keepers", members: [ids[0]])
        let stats = StatsStore()
        let before = snapshot(stats)
        let session = makeSession(stats: stats) { $0.destinationAlbumID = "dest" }
        await session.start(focusAssetID: ids[0])
        XCTAssertEqual(session.current?.id, ids[0])

        session.saveCurrentToAlbum()   // already a member → removes
        XCTAssertEqual(session.savedToAlbumCount, 0)
        session.undo()
        await session.close()

        XCTAssertEqual(session.savedToAlbumCount, 0, "clamped decrement + full increment used to leave 1")
        XCTAssertEqual(snapshot(stats) - before, CullCounters())
        XCTAssertEqual(server.members(of: "dest"), [ids[0]])
    }

    func testFavoriteThenBackThenToggleOffNetsToZero() async {
        server.addAssets(2)
        let stats = StatsStore()
        let before = snapshot(stats)
        let session = makeSession(stats: stats)
        await session.start()
        let first = session.current!.id

        session.favoriteCurrent()
        XCTAssertEqual(session.favoritedCount, 1)
        session.goToPreviousImage()
        session.favoriteCurrent()      // shown favourited → un-favourites
        await session.close()

        XCTAssertEqual(session.favoritedCount, 0)
        XCTAssertEqual(session.reviewedCount, 1)
        XCTAssertEqual(snapshot(stats) - before, CullCounters())
        XCTAssertEqual(server.asset(first)?.isFavorite, false)
    }

    func testBinRestoreTakesBackTheStatButPermanentDeleteKeepsIt() async {
        server.addAssets(3)
        let stats = StatsStore()
        let before = snapshot(stats)
        let session = makeSession(stats: stats)
        await session.start()
        let restored = session.current!.id
        session.trashCurrent()
        let deleted = session.current!.id
        session.trashCurrent()
        XCTAssertEqual(snapshot(stats) - before, CullCounters(trashed: 2))

        XCTAssertEqual(session.forgetTrashedAssets(ids: [restored], restored: true), 1)
        XCTAssertEqual(session.forgetTrashedAssets(ids: [deleted, "not-ours"], restored: false), 1)
        await session.close()

        XCTAssertEqual(session.trashedCount, 0)
        XCTAssertFalse(session.canUndo, "forgotten trashes can't be undone")
        XCTAssertEqual(snapshot(stats) - before, CullCounters(trashed: 1))
    }

    // MARK: Server failures and ordering

    func testFailedTrashIsRolledBackAndRequeued() async {
        server.addAssets(3)
        server.failTrash = true
        let stats = StatsStore()
        let before = snapshot(stats)
        let session = makeSession(stats: stats)
        await session.start()
        let first = session.current!.id

        session.trashCurrent()
        await session.close()   // drains the queued request

        XCTAssertEqual(session.trashedCount, 0, "a failed trash must not be deleted locally at the end")
        XCTAssertEqual(session.reviewedCount, 0)
        XCTAssertEqual(session.queue.last?.id, first, "the asset comes back to be dealt with")
        XCTAssertNotNil(session.errorMessage)
        XCTAssertEqual(snapshot(stats) - before, CullCounters())
    }

    func testUndoQueuedBehindItsTrashStillRunsAfterTheSessionIsReleased() async throws {
        server.addAssets(2)
        var session: CullSession? = makeSession()
        await session!.start()
        let first = session!.current!.id

        session!.trashCurrent()
        session!.undo()
        session = nil   // the deck closed

        try await waitUntil { !self.server.requests("POST", "/api/trash/restore/assets").isEmpty }
        XCTAssertEqual(server.asset(first)?.isTrashed, false,
                       "with a weak capture the restore was silently dropped")
    }

    func testTrashingALivePhotoTrashesItsMotionPart() async {
        server.add(.init(id: "still", fileName: "IMG_1.HEIC", livePhotoVideoId: "motion"))
        server.add(.init(id: "motion", type: "VIDEO", fileName: "IMG_1.MOV"))
        let session = makeSession()
        await session.start()
        session.jump(toID: "still")

        session.trashCurrent()
        await session.close()

        XCTAssertEqual(server.asset("still")?.isTrashed, true)
        XCTAssertEqual(server.asset("motion")?.isTrashed, true)
    }

    // MARK: Loading

    func testNestedTagIsMatchedAndWrittenByValue() async {
        let ids = server.addAssets(3)
        server.addTag("culled", on: [ids[0]])          // a different tag with the same leaf
        server.addTag("Trips/culled", on: [ids[1]])
        let tagsBefore = server.tagValues
        let session = makeSession {
            $0.checkedTagNames = ["Trips/culled"]
            $0.markTagName = "Trips/culled"
        }
        await session.start()

        XCTAssertEqual(Set(session.queue.map(\.id)), [ids[0], ids[2]])
        let skipped = session.current!.id
        session.skipCurrent()
        await session.close()

        XCTAssertTrue(server.isTagged(skipped, with: "Trips/culled"))
        XCTAssertEqual(server.tagValues, tagsBefore, "upserting by leaf name created a new root tag")
    }

    func testStartingFromAnAlreadyCulledAssetOpensOnIt() async {
        let ids = server.addAssets(3)
        server.addTag("culled", on: [ids[1]])
        let session = makeSession()
        await session.start(focusAssetID: ids[1])

        XCTAssertEqual(session.current?.id, ids[1])
        XCTAssertEqual(session.queue.count, 3)
        XCTAssertTrue(session.state(for: session.current!).isChecked)
    }

    func testDeletedDestinationAlbumIsClearedForTheRun() async {
        server.addAssets(2)
        let session = makeSession { $0.destinationAlbumID = "deleted-album" }
        await session.start()

        XCTAssertFalse(session.hasDestinationAlbum)
        XCTAssertNotNil(session.errorMessage)
        session.saveCurrentToAlbum()
        XCTAssertEqual(session.reviewedCount, 0, "must not pretend the add worked")
    }

    func testFilterChangeDoesNotBringBackReviewedAssets() async {
        server.addAssets(3)
        server.add(.init(id: "v0", type: "VIDEO", fileName: "MOV_0.mov"))
        let session = makeSession()
        await session.start()
        let reviewed = session.current!.id
        session.skipCurrent()

        session.setMediaFilter(.videosOnly)
        session.setMediaFilter(.all)
        await session.close()

        XCTAssertFalse(session.queue.contains { $0.id == reviewed })
        XCTAssertEqual(session.totalCount, 4)
    }

    // MARK: Offering already-culled photos

    func testTurningOnOffersCulledMidRunFetchesAndAppendsThem() async {
        let ids = server.addAssets(4)
        server.addTag("culled", on: [ids[1], ids[2]])
        let session = makeSession()
        await session.start()
        XCTAssertEqual(Set(session.queue.map(\.id)), [ids[0], ids[3]])
        let head = session.current!.id

        await session.setOffersCulled(true)

        XCTAssertTrue(session.offersCulled)
        XCTAssertEqual(session.current?.id, head, "the card on screen stays put")
        XCTAssertEqual(Set(session.queue.suffix(2).map(\.id)), [ids[1], ids[2]], "appended, not merged")
        XCTAssertTrue(session.state(for: session.queue.last!).isChecked)
        XCTAssertEqual(session.totalCount, 4)

        await session.setOffersCulled(false)
        XCTAssertEqual(Set(session.queue.map(\.id)), [ids[0], ids[3]])
    }

    func testReviewedCulledPhotoIsNotOfferedAgainAfterToggling() async {
        let ids = server.addAssets(3)
        server.addTag("culled", on: [ids[1]])
        let session = makeSession { $0.reOfferChecked = true }
        await session.start(focusAssetID: ids[1])
        session.skipCurrent()   // reviews the culled photo

        await session.setOffersCulled(false)
        await session.setOffersCulled(true)
        await session.close()

        XCTAssertFalse(session.queue.contains { $0.id == ids[1] })
        XCTAssertEqual(session.reviewedCount, 1)
    }

    func testTheCulledPhotoYouStartedFromSurvivesTurningItOff() async {
        let ids = server.addAssets(3)
        server.addTag("culled", on: [ids[1], ids[2]])
        let session = makeSession()
        await session.start(focusAssetID: ids[1])

        await session.setOffersCulled(true)
        await session.setOffersCulled(false)

        XCTAssertEqual(session.current?.id, ids[1], "picked explicitly, so it stays")
        XCTAssertFalse(session.queue.contains { $0.id == ids[2] })
    }

    // MARK: Helpers

    private func makeSession(stats: StatsStore? = nil,
                             configure: (SettingsStore) -> Void = { _ in }) -> CullSession {
        let settings = SettingsStore()
        settings.order = .newestFirst
        settings.checkedTagNames = ["culled"]
        settings.markTagName = "culled"
        settings.destinationAlbumID = ""
        settings.reOfferChecked = false
        settings.includePhotos = true
        settings.includeVideos = true
        // Never touch the real Photos library from a test.
        settings.alsoDeleteFromPhotos = false
        configure(settings)
        return CullSession(settings: settings, client: MockImmich.client(), selection: .entireLibrary,
                           stats: stats)
    }

    private func snapshot(_ stats: StatsStore) -> CullCounters {
        CullCounters(trashed: stats.trashed, skipped: stats.skipped,
                     savedToAlbum: stats.savedToAlbum, favorited: stats.favorited)
    }

    private func waitUntil(timeout: Duration = .seconds(3),
                           _ condition: @escaping () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else {
                return XCTFail("condition not met within \(timeout)")
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
