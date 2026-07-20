import Foundation
import Observation

/// Drives one culling run: loads the asset queue, applies swipe actions, and supports undo.
@MainActor
@Observable
final class CullSession {
    enum Phase: Equatable {
        case loading
        case active
        case finished
        case failed(String)
    }

    private static let pageSize = 250
    private static let maxAssets = 5000
    private static let prefetchDepth = 3

    private let client: ImmichClient
    private let selection: AlbumSelection
    private let order: CullOrder
    /// Changeable mid-run from the cull screen, unlike `order`: deciding you
    /// only want to deal with videos is a thing you realise partway through.
    private(set) var mediaFilter: MediaTypeFilter
    private let destinationAlbumID: String
    private let reOfferChecked: Bool
    /// Tags that mean "already culled" for the purpose of skipping assets.
    private let checkedTagNames: [String]
    /// The single tag written when marking an asset culled.
    private let markTagName: String

    private(set) var phase: Phase = .loading
    private(set) var queue: [ImmichAsset] = []
    private(set) var totalCount = 0
    private(set) var reviewedCount = 0
    private(set) var trashedCount = 0
    private(set) var skippedCount = 0
    private(set) var savedToAlbumCount = 0
    private(set) var favoritedCount = 0
    /// Bumped whenever a server mutation *finishes*. Views mirroring server
    /// state (the trash badge) key off this instead of the local counters,
    /// which change the instant you swipe — long before the request lands.
    private(set) var serverRevision = 0
    var errorMessage: String?

    private let alsoDeleteFromPhotos: Bool
    /// Assets trashed this session, kept so we can also remove them from the
    /// local photo library once the run finishes.
    private(set) var trashedAssets: [ImmichAsset] = []

    /// Per-asset state driving the card/grid badges and the add-or-remove
    /// decision for the toggling actions. See `AssetCullState`.
    private(set) var assetStates: [String: AssetCullState] = [:]

    /// Everything the run loaded, before the media filter. Retained so
    /// switching the filter mid-run can bring assets back without refetching.
    private var allAssets: [ImmichAsset] = []
    /// Assets that have left the queue and must not be offered again by a
    /// filter change: reviewed ones, and ones the server turned out not to have.
    private var reviewedIDs: Set<String> = []
    private var droppedIDs: Set<String> = []

    private var checkedTag: ImmichTag?
    private var undoStack: [CullActionRecord] = []
    /// Set by `goToPreviousImage`, cleared by the next action.
    private var undoSuppressed = false
    private var didRunPhotoCleanup = false
    /// In-flight server work per asset, so an undo can never overtake the
    /// action it reverses (e.g. restore landing before the delete).
    private var pendingOperations: [String: Task<Void, Never>] = [:]

    var current: ImmichAsset? { queue.first }
    var upNext: ImmichAsset? { queue.dropFirst().first }
    /// The image an undo / "previous" action would bring back, for paging preview.
    /// What `undo` would bring back — including a deletion.
    var previousAsset: ImmichAsset? { undoStack.last?.asset }
    /// False right after a back-step: see `goToPreviousImage` for why.
    var canUndo: Bool { !undoStack.isEmpty && !undoSuppressed }
    /// What "previous image" would show: the last reviewed photo that wasn't
    /// deleted, since going back steps over deletions instead of reviving them.
    var priorReviewedAsset: ImmichAsset? {
        undoStack.last(where: { $0.kind != .trash })?.asset
    }
    var canGoToPreviousImage: Bool { priorReviewedAsset != nil }
    var hasDestinationAlbum: Bool { !destinationAlbumID.isEmpty }

    func state(for asset: ImmichAsset) -> AssetCullState {
        assetStates[asset.id] ?? AssetCullState()
    }

    private let stats: StatsStore?

    init(settings: SettingsStore, client: ImmichClient, selection: AlbumSelection, stats: StatsStore? = nil) {
        self.client = client
        self.selection = selection
        self.stats = stats
        order = settings.order
        mediaFilter = settings.mediaFilter
        destinationAlbumID = settings.destinationAlbumID
        reOfferChecked = settings.reOfferChecked
        checkedTagNames = settings.checkedTagNames
        markTagName = settings.markTagName
        alsoDeleteFromPhotos = settings.alsoDeleteFromPhotos
    }

    func start() async {
        phase = .loading
        do {
            // The tag is needed for marking even when checked assets are re-offered.
            let markTag = try await client.upsertTag(named: markTagName)
            checkedTag = markTag

            // Fetched unconditionally, unlike the exclusion below: the "culled"
            // badge needs to know which assets are already tagged even when
            // they're being re-offered, which is the only time it's visible.
            let checkedIDs = try await fetchCheckedIDs(markTagID: markTag.id)

            // Both media types are fetched regardless of the filter, so
            // switching it mid-run is a local operation rather than a refetch.
            let assets = try await fetchAllAssets()
            allAssets = assets.filter { asset in
                guard asset.type == .image || asset.type == .video else { return false }
                return reOfferChecked || !checkedIDs.contains(asset.id)
            }
            queue = allAssets.filter { mediaFilter.includes($0.type) }
            await seedStates(checkedIDs: checkedIDs)
            totalCount = queue.count
            phase = queue.isEmpty ? .finished : .active
            prefetchUpcoming()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: Actions

    func trashCurrent() {
        commit(.trash)
    }

    /// Advance to the next image, tagging this one as reviewed.
    func skipCurrent() {
        commit(.skip)
    }

    /// Adds the current asset to the destination album, or takes it back out if
    /// it's already there. One gesture both ways: once something is in the
    /// album there was previously no way to remove it without leaving the app.
    func saveCurrentToAlbum() {
        guard hasDestinationAlbum else {
            errorMessage = String(localized: "Choose a destination album in Settings first.")
            return
        }
        guard let current else { return }
        commit(state(for: current).isInDestinationAlbum ? .removeFromAlbum : .saveToAlbum)
    }

    /// Favorites the current asset, or un-favorites it if it already is.
    func favoriteCurrent() {
        guard let current else { return }
        commit(state(for: current).isFavorite ? .unfavorite : .favorite)
    }

    /// Steps back to the photo before whatever was just done, leaving what was
    /// done alone. Glancing back at the last photo shouldn't quietly un-delete
    /// it, un-favorite it, or pull it out of the album — that's `undo`'s job.
    /// To change your mind about the photo you stepped back to, swipe again:
    /// favorite and add-to-album both toggle.
    ///
    /// Deletions are stepped *over* rather than re-shown, for the same reason
    /// `forgetTrashedAssets` drops them: re-showing an asset that is still
    /// trashed on the server desyncs the queue from it. Everything else still
    /// exists server-side, so re-showing it without a rollback is safe.
    ///
    /// This deliberately does not delegate to `undo`. Undo's bookkeeping
    /// decrements the per-kind counters and the lifetime stats *because* a
    /// matching server revert follows it; running that half without the revert
    /// would drift the counters, the stats and the badges permanently away from
    /// what the server actually holds.
    func goToPreviousImage() {
        while let record = undoStack.last, record.kind == .trash {
            undoStack.removeLast()
        }
        guard let record = undoStack.popLast() else { return }
        reviewedCount -= 1
        reviewedIDs.remove(record.asset.id)
        queue.insert(record.asset, at: 0)
        phase = .active
        // The record this button would have undone is gone, so `undoStack.last`
        // now points at an earlier, off-screen asset. Leaving Undo live would
        // silently revert something you aren't looking at.
        undoSuppressed = true
        prefetchUpcoming()
    }

    /// Narrows or widens what the rest of the run offers.
    ///
    /// The queue is mutated in place rather than rebuilt from `allAssets`,
    /// because its order carries information a rebuild would throw away: the
    /// rotation `jump(to:)` established, and the head position `undo` inserts
    /// at. Rebuilding would also resurrect assets `dropUnavailable` removed.
    func setMediaFilter(_ filter: MediaTypeFilter) {
        guard filter != mediaFilter else { return }
        mediaFilter = filter

        queue.removeAll { !filter.includes($0.type) }
        let present = Set(queue.map(\.id))
        // Appended, not merged in original order: anything already queued has a
        // position that means something, and newly admitted assets have none.
        queue += allAssets.filter { asset in
            filter.includes(asset.type)
                && !present.contains(asset.id)
                && !reviewedIDs.contains(asset.id)
                && !droppedIDs.contains(asset.id)
        }

        totalCount = reviewedCount + queue.count
        phase = queue.isEmpty ? .finished : .active
        prefetchUpcoming()
    }

    /// Continues the run from `asset`: it becomes the current card and the
    /// images that preceded it move to the end, so nothing is skipped for good.
    func jump(to asset: ImmichAsset) {
        guard let index = queue.firstIndex(where: { $0.id == asset.id }), index > 0 else { return }
        queue = Array(queue[index...]) + Array(queue[..<index])
        prefetchUpcoming()
    }

    /// Called when a card's image can't be loaded. Confirms with the server
    /// before discarding anything: assets whose preview simply hasn't been
    /// generated must stay reviewable, only genuinely deleted ones are dropped.
    func verifyAndDropIfMissing(_ asset: ImmichAsset) async {
        guard queue.contains(where: { $0.id == asset.id }) else { return }
        guard await client.assetExists(id: asset.id) == false else { return }
        dropUnavailable(asset)
    }

    /// Silently drops an asset the server no longer has. It was never
    /// reviewed, so nothing is counted or sent.
    func dropUnavailable(_ asset: ImmichAsset) {
        guard queue.contains(where: { $0.id == asset.id }) else { return }
        queue.removeAll { $0.id == asset.id }
        assetStates.removeValue(forKey: asset.id)
        // Remembered so a later filter change can't bring the ghost back.
        droppedIDs.insert(asset.id)
        totalCount = max(reviewedCount, totalCount - 1)
        if queue.isEmpty {
            phase = .finished
        }
        prefetchUpcoming()
    }

    /// Trashes several assets at once (from the grid), each individually undoable.
    func trashSelected(_ assets: [ImmichAsset]) {
        guard !assets.isEmpty else { return }
        let ids = assets.map(\.id)
        let idSet = Set(ids)

        queue.removeAll { idSet.contains($0.id) }
        reviewedIDs.formUnion(idSet)
        reviewedCount += assets.count
        trashedCount += assets.count
        trashedAssets.append(contentsOf: assets)
        for asset in assets {
            undoStack.append(CullActionRecord(asset: asset, kind: .trash))
            stats?.record(.trash)
        }
        undoSuppressed = false
        if queue.isEmpty {
            phase = .finished
        }
        prefetchUpcoming()

        enqueueBulk(ids) { [weak self] in
            guard let self else { return }
            do {
                try await client.trashAssets(ids: ids)
            } catch {
                errorMessage = error.localizedDescription
            }
            serverRevision += 1
        }
    }

    func undo() {
        guard let record = undoStack.popLast() else { return }
        reviewedCount -= 1
        switch record.kind {
        case .trash:
            trashedCount -= 1
            if let index = trashedAssets.lastIndex(where: { $0.id == record.asset.id }) {
                trashedAssets.remove(at: index)
            }
        case .skip: skippedCount -= 1
        case .saveToAlbum: savedToAlbumCount -= 1
        case .favorite: favoritedCount -= 1
        case .removeFromAlbum: savedToAlbumCount += 1
        case .unfavorite: favoritedCount += 1
        }
        revertState(record)
        reviewedIDs.remove(record.asset.id)
        queue.insert(record.asset, at: 0)
        stats?.revert(record.kind)
        phase = .active
        enqueue(record.asset.id) { [weak self] in
            await self?.revert(record)
        }
    }

    /// Applied optimistically, at swipe time rather than when the request
    /// lands, so the badge flips with the gesture.
    private func applyState(_ kind: CullActionKind, to assetID: String) {
        var state = assetStates[assetID] ?? AssetCullState()
        switch kind {
        case .trash: break
        case .skip: state.isChecked = true
        case .saveToAlbum:
            state.isInDestinationAlbum = true
            state.isChecked = true
        case .removeFromAlbum:
            state.isInDestinationAlbum = false
            state.isChecked = true
        case .favorite:
            state.isFavorite = true
            state.isChecked = true
        case .unfavorite:
            state.isFavorite = false
            state.isChecked = true
        }
        assetStates[assetID] = state
    }

    /// Mirror of `applyState` for `undo`. The checked flag follows `revert`'s
    /// asymmetry: undoing a removal leaves the asset marked checked, because
    /// the removal did not make it unreviewed.
    private func revertState(_ record: CullActionRecord) {
        let assetID = record.asset.id
        var state = assetStates[assetID] ?? AssetCullState()
        // Restored rather than cleared: the asset may have carried the tag
        // before the swipe, in which case the swipe didn't make it checked and
        // the undo shouldn't make it unchecked.
        switch record.kind {
        case .trash: break
        case .skip: state.isChecked = record.wasChecked
        case .saveToAlbum:
            state.isInDestinationAlbum = false
            state.isChecked = record.wasChecked
        case .favorite:
            state.isFavorite = false
            state.isChecked = record.wasChecked
        case .removeFromAlbum: state.isInDestinationAlbum = true
        case .unfavorite: state.isFavorite = true
        }
        assetStates[assetID] = state
    }

    /// Bulk variant of `enqueue`: waits for every asset's in-flight work, then
    /// becomes the pending operation for all of them.
    private func enqueueBulk(_ assetIDs: [String], _ work: @escaping @MainActor () async -> Void) {
        let previous = assetIDs.compactMap { pendingOperations[$0] }
        let task = Task { @MainActor in
            for operation in previous { await operation.value }
            await work()
        }
        for id in assetIDs {
            pendingOperations[id] = task
        }
    }

    /// Runs `work` after any operation already queued for the same asset.
    private func enqueue(_ assetID: String, _ work: @escaping @MainActor () async -> Void) {
        let previous = pendingOperations[assetID]
        pendingOperations[assetID] = Task { @MainActor in
            await previous?.value
            await work()
        }
    }

    private func commit(_ kind: CullActionKind) {
        guard let asset = queue.first else { return }
        queue.removeFirst()
        reviewedCount += 1
        switch kind {
        case .trash:
            trashedCount += 1
            trashedAssets.append(asset)
        case .skip: skippedCount += 1
        case .saveToAlbum: savedToAlbumCount += 1
        case .favorite: favoritedCount += 1
        case .removeFromAlbum: savedToAlbumCount = max(0, savedToAlbumCount - 1)
        case .unfavorite: favoritedCount = max(0, favoritedCount - 1)
        }
        // Snapshotted before applyState, which is what sets isChecked.
        let wasChecked = state(for: asset).isChecked
        applyState(kind, to: asset.id)
        reviewedIDs.insert(asset.id)
        undoStack.append(CullActionRecord(asset: asset, kind: kind, wasChecked: wasChecked))
        // Whatever was suppressing undo, acting again gives it a target.
        undoSuppressed = false
        stats?.record(kind)
        if queue.isEmpty {
            phase = .finished
        }
        prefetchUpcoming()
        enqueue(asset.id) { [weak self] in
            await self?.perform(kind, on: asset)
        }
    }

    private func perform(_ kind: CullActionKind, on asset: ImmichAsset) async {
        do {
            switch kind {
            case .trash:
                try await client.trashAssets(ids: [asset.id])
            case .skip:
                try await markChecked(asset)
            case .saveToAlbum:
                try await client.addAssets(toAlbum: destinationAlbumID, ids: [asset.id])
                try await markChecked(asset)
            case .removeFromAlbum:
                try await client.removeAssets(fromAlbum: destinationAlbumID, ids: [asset.id])
                try await markChecked(asset)
            case .favorite:
                try await client.setFavorite(ids: [asset.id], isFavorite: true)
                try await markChecked(asset)
            case .unfavorite:
                try await client.setFavorite(ids: [asset.id], isFavorite: false)
                try await markChecked(asset)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        serverRevision += 1
    }

    private func revert(_ record: CullActionRecord) async {
        do {
            switch record.kind {
            case .trash:
                try await client.restoreAssets(ids: [record.asset.id])
            case .skip:
                try await unmarkCheckedIfNewlyChecked(record)
            case .saveToAlbum:
                try await client.removeAssets(fromAlbum: destinationAlbumID, ids: [record.asset.id])
                try await unmarkCheckedIfNewlyChecked(record)
            case .favorite:
                try await client.setFavorite(ids: [record.asset.id], isFavorite: false)
                try await unmarkCheckedIfNewlyChecked(record)
            // Deliberately asymmetric with the two above: undoing a *removal*
            // restores membership but leaves the checked tag alone. The asset
            // was already reviewed before the toggle, so unmarking it here
            // would put it back in the queue on the next run.
            case .removeFromAlbum:
                try await client.addAssets(toAlbum: destinationAlbumID, ids: [record.asset.id])
            case .unfavorite:
                try await client.setFavorite(ids: [record.asset.id], isFavorite: true)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        serverRevision += 1
    }

    /// Forgets assets that were permanently deleted from the Immich trash:
    /// they can no longer be restored, so drop them from the undo stack and
    /// from this session's trashed tally.
    /// Returns how many of `ids` this session had trashed, so callers can tell
    /// them apart from items that were already in the bin beforehand.
    @discardableResult
    func forgetTrashedAssets(ids: Set<String>) -> Int {
        let removedCount = trashedAssets.count { ids.contains($0.id) }
        guard removedCount > 0 else { return 0 }
        trashedAssets.removeAll { ids.contains($0.id) }
        trashedCount = max(0, trashedCount - removedCount)
        undoStack.removeAll { $0.kind == .trash && ids.contains($0.asset.id) }
        serverRevision += 1
        return removedCount
    }

    // MARK: Local photo cleanup

    /// After the run, optionally remove the trashed items from the iPhone's
    /// photo library. iOS shows its own confirmation for the batch.
    ///
    /// Runs at most once. It is driven by a `.task` on the summary screen, and
    /// the summary is rebuilt every time the run enters `.finished` — which a
    /// media filter narrow-then-widen can now do mid-session. Without the
    /// guard, that would raise the iOS batch-delete confirmation partway
    /// through a run, repeatedly.
    func deleteTrashedFromPhotosIfEnabled() async {
        guard !didRunPhotoCleanup else { return }
        guard alsoDeleteFromPhotos, !trashedAssets.isEmpty else { return }
        didRunPhotoCleanup = true
        guard await PhotoLibraryService.ensureAccess() else { return }
        let ids = await PhotoLibraryService.localIdentifiers(matching: trashedAssets)
        await PhotoLibraryService.deleteAssets(localIdentifiers: ids)
    }

    private func markChecked(_ asset: ImmichAsset) async throws {
        guard let checkedTag else { return }
        try await client.tagAssets(tagID: checkedTag.id, assetIDs: [asset.id])
    }

    private func unmarkChecked(_ asset: ImmichAsset) async throws {
        guard let checkedTag else { return }
        try await client.untagAssets(tagID: checkedTag.id, assetIDs: [asset.id])
    }

    /// An undo only takes back the tag *this* action wrote. When the asset was
    /// already tagged before the swipe — which "Offer checked photos again"
    /// makes possible — the tag isn't ours to remove, and stripping it would
    /// re-offer an asset the user culled in an earlier run.
    private func unmarkCheckedIfNewlyChecked(_ record: CullActionRecord) async throws {
        guard !record.wasChecked else { return }
        try await unmarkChecked(record.asset)
    }

    // MARK: Loading

    /// Fetches the full result set up front so trashing assets mid-session
    /// cannot shift server-side pagination underneath us.
    private func fetchAllAssets() async throws -> [ImmichAsset] {
        try await client.fetchAssets(albumIDs: selection.albumIDs, tagIDs: nil,
                                     order: order.apiValue, limit: Self.maxAssets)
    }

    /// Records what is already true of each queued asset, so the badges are
    /// right on the very first card rather than only after you act on it.
    ///
    /// Album membership needs its own request: the search response says nothing
    /// about which albums an asset belongs to. A failure here is not fatal —
    /// the badge is missing information, not wrong — so it degrades to "not in
    /// the album" rather than failing the session.
    private func seedStates(checkedIDs: Set<String>) async {
        var albumMemberIDs: Set<String> = []
        if hasDestinationAlbum {
            let members = try? await client.fetchAssets(albumIDs: [destinationAlbumID], tagIDs: nil,
                                                        order: order.apiValue, limit: Self.maxAssets)
            albumMemberIDs = Set((members ?? []).map(\.id))
        }

        assetStates = allAssets.reduce(into: [:]) { states, asset in
            states[asset.id] = AssetCullState(
                isFavorite: asset.isFavorite ?? false,
                isInDestinationAlbum: albumMemberIDs.contains(asset.id),
                isChecked: checkedIDs.contains(asset.id)
            )
        }
    }

    /// Every asset carrying any of the configured "already culled" tags.
    ///
    /// One request per tag, in parallel: each pages to `limit: .max`, so doing
    /// them in series would visibly delay the first card on a large library.
    /// They're fetched separately rather than passed to the search as one
    /// `tagIds` array because Immich's AND/OR semantics for multiple tags
    /// aren't worth guessing at — a union is what's wanted, unambiguously.
    private func fetchCheckedIDs(markTagID: String) async throws -> Set<String> {
        let all = try await client.tags()
        var tagIDs = Set(all.filter { checkedTagNames.contains($0.name) }.map(\.id))
        // Whatever we write, we honour: an asset this app marked must count as
        // culled even if the mark tag was never added to the exclusion list.
        tagIDs.insert(markTagID)

        return try await withThrowingTaskGroup(of: [ImmichAsset].self) { group in
            for tagID in tagIDs {
                group.addTask { [client, order] in
                    try await client.fetchAssets(albumIDs: nil, tagIDs: [tagID],
                                                 order: order.apiValue, limit: .max)
                }
            }
            var ids: Set<String> = []
            for try await assets in group {
                ids.formUnion(assets.map(\.id))
            }
            return ids
        }
    }

    private func prefetchUpcoming() {
        for asset in queue.prefix(Self.prefetchDepth) where asset.type == .image {
            ImageLoader.shared.prefetch(url: client.thumbnailURL(assetID: asset.id), apiKey: client.apiKey)
        }
    }
}
