import Foundation
import Observation

/// Drives one culling run: loads the asset queue, applies swipe actions, and supports undo.
///
/// Every swipe is applied locally at once (optimistically) and sent to the
/// server behind it. The local bookkeeping lives in two halves —
/// `applyLocal` and `unapplyLocal` — that commit, undo, and failure rollback
/// all share, so no path can update one piece of state and forget another.
@MainActor
@Observable
final class CullSession {
    enum Phase: Equatable {
        case loading
        case active
        case finished
        case failed(String)
    }

    private static let maxAssets = 5000
    private static let prefetchDepth = 3

    private let client: ImmichClient
    private let selection: AlbumSelection
    private let order: CullOrder
    /// Changeable mid-run from the cull screen, unlike `order`: deciding you
    /// only want to deal with videos is a thing you realise partway through.
    private(set) var mediaFilter: MediaTypeFilter
    /// Cleared for this run by `start()` if the album no longer exists, so a
    /// deleted album reads as "none chosen" instead of failing every swipe.
    private(set) var destinationAlbumID: String
    /// Whether assets that were already culled before this run are offered.
    /// Starts from Settings, switchable mid-run via `setOffersCulled`.
    private(set) var offersCulled: Bool
    /// True while turning `offersCulled` on fetches the culled assets the run
    /// skipped at load.
    private(set) var isLoadingCulled = false
    /// Tag values (full paths) that mean "already culled" for skipping assets.
    private let checkedTagNames: [String]
    /// The single tag value written when marking an asset culled.
    private let markTagName: String

    private(set) var phase: Phase = .loading
    private(set) var queue: [ImmichAsset] = []
    /// Assets that have left the queue by being acted on. Also what keeps a
    /// filter change from offering them again.
    private(set) var reviewedIDs: Set<String> = []
    /// Bumped whenever a server mutation *finishes*. Views mirroring server
    /// state (the trash badge) key off this instead of the local counters,
    /// which change the instant you swipe — long before the request lands.
    private(set) var serverRevision = 0
    var errorMessage: String?

    private let alsoDeleteFromPhotos: Bool
    /// Assets trashed this session, kept so we can also remove them from the
    /// local photo library when the run ends. A trash the server rejected is
    /// rolled back out of here, so it can never be deleted locally.
    private(set) var trashedAssets: [ImmichAsset] = []
    /// True while the end-of-run cleanup scans the local photo library.
    private(set) var isSearchingPhotoLibrary = false

    /// Per-asset state driving the card/grid badges and the add-or-remove
    /// decision for the toggling actions. See `AssetCullState`.
    private(set) var assetStates: [String: AssetCullState] = [:]
    /// `assetStates` as loaded, before any swipe; the counters are the
    /// difference between the two.
    private var initialStates: [String: AssetCullState] = [:]
    /// The latest action applied to each asset this session.
    private var lastAction: [String: CullActionKind] = [:]
    /// Each loaded asset's position in the fetch, for grids that need a stable
    /// order while the queue itself is rotated by `jump(to:)`.
    private(set) var loadOrder: [String: Int] = [:]

    /// Everything the run loaded, before the media filter. Retained so
    /// switching the filter mid-run can bring assets back without refetching.
    private var allAssets: [ImmichAsset] = []
    /// Assets the server turned out not to have; never offered again.
    private var droppedIDs: Set<String> = []
    /// Assets that carried a culled tag when the run loaded. Tags written by
    /// this run don't count: those assets are reviewed, and handled as such.
    private var culledAtLoad: Set<String> = []
    /// Whether `allAssets` includes the culled ones — true when the run
    /// started with them offered, or once a toggle fetched them.
    private var didFetchCulled = false
    /// The asset the run was opened on. Offered even if culled: the user
    /// picked it.
    private var focusAssetID: String?
    private var albumMemberIDs: Set<String> = []

    private var checkedTag: ImmichTag?
    private var undoStack: [CullActionRecord] = []
    /// Set by `goToPreviousImage`, cleared by the next action.
    private var undoSuppressed = false
    /// Trashed assets already handed to the local-library cleanup.
    private var cleanedIDs: Set<String> = []
    /// In-flight server work per asset, so an undo can never overtake the
    /// action it reverses (e.g. restore landing before the delete).
    private var pendingOperations: [String: PendingOperation] = [:]

    private struct PendingOperation {
        let token: UUID
        let task: Task<Void, Never>
    }

    // MARK: Derived state

    var current: ImmichAsset? { queue.first }
    var upNext: ImmichAsset? { queue.dropFirst().first }
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

    var reviewedCount: Int { reviewedIDs.count }
    var totalCount: Int { reviewedCount + queue.count }

    /// What this session has done, derived from its state rather than counted
    /// per swipe — see `CullCounters` for the drift that counting caused.
    /// Favourites and album additions are *net*: an asset counts when it ends
    /// the session favourited (or in the album) and didn't start that way.
    var counters: CullCounters {
        var counters = CullCounters(trashed: trashedAssets.count)
        counters.skipped = lastAction.values.count { $0 == .skip }
        for (id, state) in assetStates {
            let initial = initialStates[id] ?? AssetCullState()
            if state.isFavorite && !initial.isFavorite { counters.favorited += 1 }
            if state.isInDestinationAlbum && !initial.isInDestinationAlbum { counters.savedToAlbum += 1 }
        }
        return counters
    }

    var trashedCount: Int { trashedAssets.count }
    var skippedCount: Int { counters.skipped }
    var savedToAlbumCount: Int { counters.savedToAlbum }
    var favoritedCount: Int { counters.favorited }

    func state(for asset: ImmichAsset) -> AssetCullState {
        assetStates[asset.id] ?? AssetCullState()
    }

    private let stats: StatsStore?

    /// `mediaFilter` overrides the Settings default — a grid launching the deck
    /// passes its own, so the photo you started from is actually in the run.
    init(settings: SettingsStore, client: ImmichClient, selection: AlbumSelection,
         stats: StatsStore? = nil, mediaFilter: MediaTypeFilter? = nil) {
        self.client = client
        self.selection = selection
        self.stats = stats
        order = settings.order
        self.mediaFilter = mediaFilter ?? settings.mediaFilter
        destinationAlbumID = settings.destinationAlbumID
        offersCulled = settings.reOfferChecked
        checkedTagNames = settings.checkedTagNames
        markTagName = settings.markTagName
        alsoDeleteFromPhotos = settings.alsoDeleteFromPhotos
    }

    /// Loads the run. `focusAssetID` opens it on that asset — even one that is
    /// already culled and would otherwise be excluded, since the user picked it.
    func start(focusAssetID: String? = nil) async {
        phase = .loading
        do {
            // The tag is needed for marking even when checked assets are re-offered.
            let markTag = try await client.upsertTag(value: markTagName)
            checkedTag = markTag

            // Fetched unconditionally, unlike the exclusion below: the "culled"
            // badge needs to know which assets are already tagged even when
            // they're being re-offered, which is the only time it's visible.
            let checkedIDs = try await AssetStateSeeder.checkedIDs(client: client, tagValues: checkedTagNames,
                                                                   alsoTagID: markTag.id)
            await validateDestinationAlbum()

            culledAtLoad = checkedIDs
            self.focusAssetID = focusAssetID
            didFetchCulled = offersCulled
            var assets = try await fetchAllAssets(excluding: offersCulled ? [] : checkedIDs)
            if let focusAssetID, !assets.contains(where: { $0.id == focusAssetID }),
               let focus = try? await client.asset(id: focusAssetID),
               !(focus.isTrashed ?? false), mediaFilter.includes(focus.type) {
                assets.append(focus)
            }

            allAssets = assets
            loadOrder = Dictionary(uniqueKeysWithValues: assets.enumerated().map { ($1.id, $0) })
            queue = allAssets.filter(isOfferable)
            await seedStates(checkedIDs: checkedIDs)
            phase = queue.isEmpty ? .finished : .active
            if let focusAssetID {
                jump(toID: focusAssetID)
            }
            prefetchUpcoming()
            assertConsistent()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Ends the run. Waits for queued server work — so nothing the user did is
    /// lost when the screen closes — then removes this session's trashes from
    /// the local photo library if that's enabled. iOS/macOS confirm the batch.
    ///
    /// This runs on *exit*, not when the queue first empties. Hanging it off
    /// the summary screen skipped it entirely when a run was closed early, and
    /// ran it before an "Undo Last" could restore something it had deleted.
    func close() async {
        await waitForPendingWork()
        guard alsoDeleteFromPhotos else { return }
        let toClean = trashedAssets.filter { !cleanedIDs.contains($0.id) }
        guard !toClean.isEmpty else { return }
        cleanedIDs.formUnion(toClean.map(\.id))
        _ = await TrashPurger.deleteLocalCopies(of: toClean) { searching in
            isSearchingPhotoLibrary = searching
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
    /// This deliberately does not delegate to `undo`, and touches only the
    /// queue and the reviewed set: the action stays applied on the server, so
    /// `lastAction` and the asset's state stay too — which is what keeps the
    /// counters (and lifetime stats) unchanged, and stops a re-swipe of the
    /// same action from counting the photo twice.
    func goToPreviousImage() {
        mutate {
            while let record = undoStack.last, record.kind == .trash {
                undoStack.removeLast()
            }
            guard let record = undoStack.popLast() else { return }
            reviewedIDs.remove(record.asset.id)
            queue.insert(record.asset, at: 0)
            phase = .active
            // The record this button would have undone is gone, so `undoStack.last`
            // now points at an earlier, off-screen asset. Leaving Undo live would
            // silently revert something you aren't looking at.
            undoSuppressed = true
        }
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
        refilterQueue()
    }

    /// Offers — or stops offering — assets that were already culled before this
    /// run, for the rest of it. Same in-place rules as `setMediaFilter`.
    ///
    /// Turning it on for a run that loaded without them fetches them first
    /// (once); a failed fetch leaves the setting off and says so.
    func setOffersCulled(_ offered: Bool) async {
        guard offered != offersCulled, !isLoadingCulled else { return }
        if offered && !didFetchCulled {
            isLoadingCulled = true
            defer { isLoadingCulled = false }
            do {
                try await loadCulledAssets()
            } catch {
                errorMessage = String(localized: "Couldn't load the already-culled photos: \(error.localizedDescription)")
                return
            }
        }
        offersCulled = offered
        refilterQueue()
    }

    /// Whether `asset` belongs in the queue under the current filters.
    private func isOfferable(_ asset: ImmichAsset) -> Bool {
        mediaFilter.includes(asset.type)
            && !reviewedIDs.contains(asset.id)
            && !droppedIDs.contains(asset.id)
            && (offersCulled || !culledAtLoad.contains(asset.id) || asset.id == focusAssetID)
    }

    /// Re-applies the filters to the queue in place. Not rebuilt from
    /// `allAssets`, because the queue's order carries information a rebuild
    /// would throw away: the rotation `jump(to:)` established, and the head
    /// position `undo` inserts at. Newly admitted assets are appended, not
    /// merged back in load order — they have no position that means anything.
    private func refilterQueue() {
        mutate {
            queue.removeAll { !isOfferable($0) }
            let present = Set(queue.map(\.id))
            queue += allAssets.filter { isOfferable($0) && !present.contains($0.id) }
            phase = queue.isEmpty ? .finished : .active
        }
        prefetchUpcoming()
    }

    /// Fetches the culled assets a run that started without them skipped.
    private func loadCulledAssets() async throws {
        let known = Set(allAssets.map(\.id))
        let culled = culledAtLoad
        let fetched = try await client.fetchAssets(
            albumIDs: selection.albumIDs, tagIDs: nil, order: order.apiValue, limit: Self.maxAssets,
            isNotInAlbum: selection.isNotInAlbum ? true : nil, visibility: "timeline"
        ) { asset in
            (asset.type == .image || asset.type == .video) && culled.contains(asset.id) && !known.contains(asset.id)
        }
        let states = AssetStateSeeder.states(for: fetched, checkedIDs: culled, albumMemberIDs: albumMemberIDs)
        for (index, asset) in fetched.enumerated() {
            loadOrder[asset.id] = allAssets.count + index
            assetStates[asset.id] = states[asset.id]
            initialStates[asset.id] = states[asset.id]
        }
        allAssets += fetched
        didFetchCulled = true
    }

    /// Continues the run from `asset`: it becomes the current card and the
    /// images that preceded it move to the end, so nothing is skipped for good.
    func jump(to asset: ImmichAsset) {
        guard let index = queue.firstIndex(where: { $0.id == asset.id }), index > 0 else { return }
        queue = Array(queue[index...]) + Array(queue[..<index])
        prefetchUpcoming()
    }

    /// Same as `jump(to:)` but by ID — used to open the deck already positioned
    /// on the photo tapped in a grid.
    func jump(toID id: String) {
        guard let asset = queue.first(where: { $0.id == id }) else { return }
        jump(to: asset)
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
    /// reviewed, so nothing is sent.
    func dropUnavailable(_ asset: ImmichAsset) {
        guard queue.contains(where: { $0.id == asset.id }) else { return }
        mutate {
            queue.removeAll { $0.id == asset.id }
            assetStates.removeValue(forKey: asset.id)
            // Remembered so a later filter change can't bring the ghost back.
            droppedIDs.insert(asset.id)
            if queue.isEmpty {
                phase = .finished
            }
        }
        prefetchUpcoming()
    }

    /// Trashes several assets at once (from the grid), each individually undoable.
    func trashSelected(_ assets: [ImmichAsset]) {
        guard !assets.isEmpty else { return }
        let idSet = Set(assets.map(\.id))
        let records = assets.map { record(for: $0, kind: .trash) }

        mutate {
            queue.removeAll { idSet.contains($0.id) }
            records.forEach(applyLocal)
            undoSuppressed = false
            if queue.isEmpty {
                phase = .finished
            }
        }
        prefetchUpcoming()

        // Keyed on the visible still IDs, but the server call also carries any
        // paired Live Photo movies so they're trashed together.
        let serverIDs = assets.idsIncludingLivePhotoPairs
        enqueue(assets.map(\.id)) {
            do {
                try await self.client.trashAssets(ids: serverIDs)
            } catch {
                for record in records {
                    self.rollBack(record, after: error)
                }
            }
            self.serverRevision += 1
        }
    }

    func undo() {
        guard let record = undoStack.popLast() else { return }
        mutate {
            unapplyLocal(record)
            queue.insert(record.asset, at: 0)
            phase = .active
        }
        prefetchUpcoming()
        enqueue([record.asset.id]) {
            await self.revert(record)
        }
    }

    /// Forgets assets that left the Immich trash through the bin: they are no
    /// longer this session's to undo, nor to delete locally. Returns how many of
    /// `ids` this session had trashed, so callers can tell them apart from items
    /// that were already in the bin beforehand.
    ///
    /// `restored` decides the lifetime stats: a restore takes the trash back
    /// (like undo), a permanent delete does not — the photo *was* deleted.
    @discardableResult
    func forgetTrashedAssets(ids: Set<String>, restored: Bool) -> Int {
        let removedCount = trashedAssets.count { ids.contains($0.id) }
        guard removedCount > 0 else { return 0 }
        let forget = {
            self.trashedAssets.removeAll { ids.contains($0.id) }
            self.undoStack.removeAll { $0.kind == .trash && ids.contains($0.asset.id) }
            for id in ids where self.lastAction[id] == .trash {
                self.lastAction[id] = nil
            }
        }
        if restored {
            mutate(forget)
        } else {
            forget()
            assertConsistent()
        }
        serverRevision += 1
        return removedCount
    }

    // MARK: Local bookkeeping

    private func record(for asset: ImmichAsset, kind: CullActionKind) -> CullActionRecord {
        // Snapshotted before applyState, which is what sets isChecked.
        CullActionRecord(asset: asset, kind: kind, wasChecked: state(for: asset).isChecked,
                         priorAction: lastAction[asset.id])
    }

    /// The local half of an action. Does not touch the queue.
    private func applyLocal(_ record: CullActionRecord) {
        let id = record.asset.id
        reviewedIDs.insert(id)
        lastAction[id] = record.kind
        if record.kind == .trash {
            trashedAssets.append(record.asset)
        }
        applyState(record.kind, to: id)
        undoStack.append(record)
    }

    /// Exact inverse of `applyLocal`, minus the undo stack (the caller has
    /// already taken the record off it). Does not touch the queue.
    private func unapplyLocal(_ record: CullActionRecord) {
        let id = record.asset.id
        reviewedIDs.remove(id)
        lastAction[id] = record.priorAction
        if record.kind == .trash, let index = trashedAssets.lastIndex(where: { $0.id == id }) {
            trashedAssets.remove(at: index)
        }
        revertState(record)
    }

    /// Runs a state change, then moves the lifetime stats by exactly what it
    /// changed in the session counters, and checks the invariants.
    private func mutate(_ change: () -> Void) {
        let before = counters
        change()
        stats?.apply(counters - before)
        assertConsistent()
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

    /// Puts an asset back at the end of the queue, if the filter admits it.
    private func requeue(_ asset: ImmichAsset) {
        guard !queue.contains(where: { $0.id == asset.id }) else { return }
        if mediaFilter.includes(asset.type) {
            queue.append(asset)
            phase = .active
        }
    }

    // MARK: Server work

    private func commit(_ kind: CullActionKind) {
        guard let asset = queue.first else { return }
        let record = record(for: asset, kind: kind)
        mutate {
            queue.removeFirst()
            applyLocal(record)
            // Whatever was suppressing undo, acting again gives it a target.
            undoSuppressed = false
            if queue.isEmpty {
                phase = .finished
            }
        }
        prefetchUpcoming()
        enqueue([asset.id]) {
            await self.perform(record)
        }
    }

    /// Runs `work` after any operation already queued for the same assets, then
    /// becomes the pending operation for all of them.
    ///
    /// `work` captures the session strongly on purpose. A weak capture let a
    /// chained operation — an undo waiting behind its trash — find the session
    /// already released when the deck closed, and silently not run: the asset
    /// stayed trashed on the server though the user had undone it. The cycle
    /// ends when the task finishes and removes itself.
    private func enqueue(_ assetIDs: [String], _ work: @escaping @MainActor () async -> Void) {
        let previous = assetIDs.compactMap { pendingOperations[$0]?.task }
        let token = UUID()
        let task = Task { @MainActor in
            for operation in previous { await operation.value }
            await work()
            for id in assetIDs where self.pendingOperations[id]?.token == token {
                self.pendingOperations[id] = nil
            }
        }
        for id in assetIDs {
            pendingOperations[id] = PendingOperation(token: token, task: task)
        }
    }

    private func waitForPendingWork() async {
        // Each finished task removes itself, so anything still listed after a
        // pass was enqueued during it.
        while !pendingOperations.isEmpty {
            for task in pendingOperations.values.map(\.task) {
                await task.value
            }
        }
    }

    private func perform(_ record: CullActionRecord) async {
        let asset = record.asset
        do {
            switch record.kind {
            case .trash:
                // Live Photo: the paired .mov goes to the trash with the still.
                try await client.trashAssets(ids: asset.idsIncludingLivePhotoPair)
            case .skip:
                try await markChecked(asset)
            case .saveToAlbum:
                try await client.addAssets(toAlbum: destinationAlbumID, ids: [asset.id])
            case .removeFromAlbum:
                try await client.removeAssets(fromAlbum: destinationAlbumID, ids: [asset.id])
            case .favorite:
                try await client.setFavorite(ids: [asset.id], isFavorite: true)
            case .unfavorite:
                try await client.setFavorite(ids: [asset.id], isFavorite: false)
            }
        } catch {
            rollBack(record, after: error)
            serverRevision += 1
            return
        }

        // The action itself landed; the review tag is secondary to it.
        if record.kind != .trash && record.kind != .skip {
            do {
                try await markChecked(asset)
            } catch {
                if !record.wasChecked {
                    assetStates[asset.id]?.isChecked = false
                }
                errorMessage = String(localized: "Couldn't mark “\(asset.originalFileName)” as culled: \(error.localizedDescription)")
            }
        }
        serverRevision += 1
    }

    /// Takes back the local half of an action the server rejected, so nothing
    /// claims an effect that didn't happen — in particular, a failed trash must
    /// not be deleted from the photo library at the end of the run. The asset
    /// goes back to the end of the queue to be dealt with again.
    private func rollBack(_ record: CullActionRecord, after error: Error) {
        let id = record.asset.id
        mutate {
            if let index = undoStack.lastIndex(where: { $0.id == record.id }) {
                unapplyLocal(undoStack.remove(at: index))
                requeue(record.asset)
            } else if record.kind == .trash, trashedAssets.contains(where: { $0.id == id }) {
                // Its record was stepped over by a back-step, but it still
                // counts as trashed here.
                unapplyLocal(record)
                requeue(record.asset)
            } else if queue.contains(where: { $0.id == id }), lastAction[id] == record.kind {
                // Re-shown by a back-step with the failed action still applied.
                revertState(record)
                lastAction[id] = record.priorAction
            }
            // Otherwise it was already undone: nothing local is left to take back.
        }
        errorMessage = String(localized: "Couldn't update “\(record.asset.originalFileName)”: \(error.localizedDescription) It's back in the queue.")
    }

    private func revert(_ record: CullActionRecord) async {
        do {
            switch record.kind {
            case .trash:
                // Restore the paired Live Photo movie alongside the still.
                try await client.restoreAssets(ids: record.asset.idsIncludingLivePhotoPair)
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
            reapplyAfterFailedUndo(record, error: error)
        }
        serverRevision += 1
    }

    /// An undo the server rejected leaves the action in effect, so the local
    /// state goes back to saying so — provided the asset is still sitting in
    /// the queue untouched. The record returns to the undo stack to retry.
    private func reapplyAfterFailedUndo(_ record: CullActionRecord, error: Error) {
        let id = record.asset.id
        if let index = queue.firstIndex(where: { $0.id == id }) {
            mutate {
                queue.remove(at: index)
                applyLocal(record)
                if queue.isEmpty {
                    phase = .finished
                }
            }
        }
        errorMessage = String(localized: "Couldn't undo “\(record.asset.originalFileName)”: \(error.localizedDescription)")
    }

    private func markChecked(_ asset: ImmichAsset) async throws {
        guard let checkedTag else { return }
        try await client.tagAssets(tagID: checkedTag.id, assetIDs: [asset.id])
    }

    /// An undo only takes back the tag *this* action wrote. When the asset was
    /// already tagged before the swipe — which "Offer checked photos again"
    /// makes possible — the tag isn't ours to remove, and stripping it would
    /// re-offer an asset the user culled in an earlier run.
    private func unmarkCheckedIfNewlyChecked(_ record: CullActionRecord) async throws {
        guard !record.wasChecked, let checkedTag else { return }
        try await client.untagAssets(tagID: checkedTag.id, assetIDs: [record.asset.id])
    }

    // MARK: Loading

    /// Fetches the full result set up front so trashing assets mid-session
    /// cannot shift server-side pagination underneath us.
    ///
    /// Exclusion happens *inside* the paging, so the cap counts only assets
    /// still to review. Filtering after a capped fetch meant that once the
    /// first 5000 were culled, nothing beyond them could ever be offered.
    private func fetchAllAssets(excluding excludedIDs: Set<String>) async throws -> [ImmichAsset] {
        try await client.fetchAssets(albumIDs: selection.albumIDs, tagIDs: nil,
                                     order: order.apiValue, limit: Self.maxAssets,
                                     isNotInAlbum: selection.isNotInAlbum ? true : nil,
                                     visibility: "timeline") { asset in
            (asset.type == .image || asset.type == .video) && !excludedIDs.contains(asset.id)
        }
    }

    /// A destination album deleted on the server would otherwise make every
    /// "add to album" swipe look like it worked while the server rejects it.
    /// A failed album listing is not evidence of anything, so it's ignored.
    private func validateDestinationAlbum() async {
        guard hasDestinationAlbum, let albums = try? await client.albums() else { return }
        if !albums.contains(where: { $0.id == destinationAlbumID }) {
            destinationAlbumID = ""
            errorMessage = String(localized: "The pull-down album no longer exists on the server. Choose another in Settings.")
        }
    }

    /// Records what is already true of each queued asset, so the badges are
    /// right on the very first card rather than only after you act on it.
    ///
    /// A failed album-membership lookup is not fatal — the badge is missing
    /// information, not wrong — so it degrades to "not in the album".
    private func seedStates(checkedIDs: Set<String>) async {
        albumMemberIDs = (try? await AssetStateSeeder.albumMemberIDs(client: client, albumID: destinationAlbumID)) ?? []
        assetStates = AssetStateSeeder.states(for: allAssets, checkedIDs: checkedIDs, albumMemberIDs: albumMemberIDs)
        initialStates = assetStates
    }

    private func prefetchUpcoming() {
        for asset in queue.prefix(Self.prefetchDepth) where asset.type == .image {
            ImageLoader.shared.prefetch(url: client.thumbnailURL(assetID: asset.id), apiKey: client.apiKey)
        }
    }

    /// Debug-only cross-checks of the bookkeeping, run after every mutation.
    /// Each one is a way the queue, counters and server have drifted apart
    /// before; a failure here points at the mutation that broke it.
    private func assertConsistent() {
        #if DEBUG
        let queuedIDs = queue.map(\.id)
        assert(Set(queuedIDs).count == queuedIDs.count, "an asset is queued twice")
        assert(reviewedIDs.isDisjoint(with: queuedIDs), "a reviewed asset is still queued")
        assert(Set(trashedAssets.map(\.id)).count == trashedAssets.count, "an asset is counted as trashed twice")
        assert(trashedAssets.allSatisfy { reviewedIDs.contains($0.id) }, "a trashed asset isn't reviewed")
        assert(undoStack.allSatisfy { reviewedIDs.contains($0.asset.id) }, "an undo record's asset isn't reviewed")
        assert(Set(undoStack.map(\.asset.id)).count == undoStack.count, "an asset has two undo records")
        #endif
    }
}
