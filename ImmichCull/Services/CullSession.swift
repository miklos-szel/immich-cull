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
    private let mediaFilter: MediaTypeFilter
    private let destinationAlbumID: String
    private let reOfferChecked: Bool
    private let checkedTagName: String

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

    private var checkedTag: ImmichTag?
    private var undoStack: [CullActionRecord] = []
    /// In-flight server work per asset, so an undo can never overtake the
    /// action it reverses (e.g. restore landing before the delete).
    private var pendingOperations: [String: Task<Void, Never>] = [:]

    var current: ImmichAsset? { queue.first }
    var upNext: ImmichAsset? { queue.dropFirst().first }
    /// The image an undo / "previous" action would bring back, for paging preview.
    var previousAsset: ImmichAsset? { undoStack.last?.asset }
    var canUndo: Bool { !undoStack.isEmpty }
    var hasDestinationAlbum: Bool { !destinationAlbumID.isEmpty }

    private let stats: StatsStore?

    init(settings: SettingsStore, client: ImmichClient, selection: AlbumSelection, stats: StatsStore? = nil) {
        self.client = client
        self.selection = selection
        self.stats = stats
        order = settings.order
        mediaFilter = settings.mediaFilter
        destinationAlbumID = settings.destinationAlbumID
        reOfferChecked = settings.reOfferChecked
        checkedTagName = settings.checkedTagName
        alsoDeleteFromPhotos = settings.alsoDeleteFromPhotos
    }

    func start() async {
        phase = .loading
        do {
            // The tag is needed for marking even when checked assets are re-offered.
            let tag = try await client.upsertTag(named: checkedTagName)
            checkedTag = tag

            var checkedIDs: Set<String> = []
            if !reOfferChecked {
                checkedIDs = try await fetchCheckedIDs(tagID: tag.id)
            }

            let assets = try await fetchAllAssets()
            queue = assets.filter { asset in
                (asset.type == .image || asset.type == .video) && !checkedIDs.contains(asset.id)
            }
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

    func saveCurrentToAlbum() {
        guard hasDestinationAlbum else {
            errorMessage = String(localized: "Choose a destination album in Settings first.")
            return
        }
        commit(.saveToAlbum)
    }

    func favoriteCurrent() {
        commit(.favorite)
    }

    /// Steps back to the previously reviewed image. Going back also rolls back
    /// what was done to that image — leaving it trashed/tagged while showing it
    /// as the current card would put the queue and the server out of sync.
    func goToPreviousImage() {
        undo()
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
        reviewedCount += assets.count
        trashedCount += assets.count
        trashedAssets.append(contentsOf: assets)
        for asset in assets {
            undoStack.append(CullActionRecord(asset: asset, kind: .trash))
            stats?.record(.trash)
        }
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
        }
        queue.insert(record.asset, at: 0)
        stats?.revert(record.kind)
        phase = .active
        enqueue(record.asset.id) { [weak self] in
            await self?.revert(record)
        }
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
        }
        undoStack.append(CullActionRecord(asset: asset, kind: kind))
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
            case .favorite:
                try await client.setFavorite(ids: [asset.id], isFavorite: true)
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
                try await unmarkChecked(record.asset)
            case .saveToAlbum:
                try await client.removeAssets(fromAlbum: destinationAlbumID, ids: [record.asset.id])
                try await unmarkChecked(record.asset)
            case .favorite:
                try await client.setFavorite(ids: [record.asset.id], isFavorite: false)
                try await unmarkChecked(record.asset)
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
    func deleteTrashedFromPhotosIfEnabled() async {
        guard alsoDeleteFromPhotos, !trashedAssets.isEmpty else { return }
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

    // MARK: Loading

    /// Fetches the full result set up front so trashing assets mid-session
    /// cannot shift server-side pagination underneath us.
    private func fetchAllAssets() async throws -> [ImmichAsset] {
        try await client.fetchAssets(albumIDs: selection.albumIDs, tagIDs: nil,
                                     order: order.apiValue, limit: Self.maxAssets,
                                     type: mediaFilter.searchType)
    }

    private func fetchCheckedIDs(tagID: String) async throws -> Set<String> {
        let checked = try await client.fetchAssets(albumIDs: nil, tagIDs: [tagID],
                                                   order: order.apiValue, limit: .max)
        return Set(checked.map(\.id))
    }

    private func prefetchUpcoming() {
        for asset in queue.prefix(Self.prefetchDepth) where asset.type == .image {
            ImageLoader.shared.prefetch(url: client.thumbnailURL(assetID: asset.id), apiKey: client.apiKey)
        }
    }
}
