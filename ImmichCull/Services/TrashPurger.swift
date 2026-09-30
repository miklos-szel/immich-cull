import Foundation

/// The one place local copies are removed alongside an Immich delete, so the
/// iOS and macOS bins, and the browse grids, all do it in the same order with
/// the same pairing.
@MainActor
enum TrashPurger {
    /// Removes the local copies of `assets` from the photo library.
    /// `searching` brackets the (possibly slow) library scan so callers can show
    /// progress before the system confirmation appears.
    ///
    /// Returns true when copies may remain: no library access, or the user
    /// declined the system prompt. Finding nothing to delete is not "remain".
    static func deleteLocalCopies(of assets: [ImmichAsset],
                                  searching: (Bool) -> Void = { _ in }) async -> Bool {
        guard !assets.isEmpty else { return false }
        // Without access we cannot even look — precisely the case where
        // Immich's auto-backup can silently put the deleted photo back.
        guard await PhotoLibraryService.ensureAccess() else { return true }
        searching(true)
        let localIDs = await PhotoLibraryService.localIdentifiers(matching: assets)
        searching(false)
        guard !localIDs.isEmpty else { return false }
        return await PhotoLibraryService.deleteAssets(localIdentifiers: localIDs) == false
    }

    /// Permanently deletes `assets` (and their Live Photo movies) from Immich,
    /// removing local copies *first*.
    ///
    /// Local-first closes the window in which a photo is on the device but no
    /// longer on the server — the state in which the official Immich app's
    /// auto-backup uploads it again, undoing the delete. A failed local step
    /// doesn't abort the server delete (the user asked for it gone); the
    /// return value says whether to warn.
    static func permanentlyDelete(_ assets: [ImmichAsset], client: ImmichClient,
                                  searching: (Bool) -> Void = { _ in }) async throws -> Bool {
        let localCopiesRemain = await deleteLocalCopies(of: assets, searching: searching)
        try await client.permanentlyDeleteAssets(ids: assets.idsIncludingLivePhotoPairs)
        return localCopiesRemain
    }
}
