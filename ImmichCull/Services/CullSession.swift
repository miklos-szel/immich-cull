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
    }

    /// Forgets assets that were permanently deleted from the Immich trash:
    /// they can no longer be restored, so drop them from the undo stack and
    /// from this session's trashed tally.
    func forgetTrashedAssets(ids: Set<String>) {
        let removedCount = trashedAssets.count { ids.contains($0.id) }
        guard removedCount > 0 else { return }
        trashedAssets.removeAll { ids.contains($0.id) }
        trashedCount = max(0, trashedCount - removedCount)
        undoStack.removeAll { $0.kind == .trash && ids.contains($0.asset.id) }
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
                                     order: order.apiValue, limit: Self.maxAssets)
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
