import Photos

/// Matches Immich assets to local iPhone photos and deletes them.
/// Matching is best-effort: by original filename, narrowed by capture date.
enum PhotoLibraryService {
    /// True once we have (or are granted) read-write access to the photo library.
    static func ensureAccess() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let granted = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            return granted == .authorized || granted == .limited
        default:
            return false
        }
    }

    /// Finds local identifiers of photos matching the given assets by filename
    /// (and capture date when available), for later deletion.
    static func localIdentifiers(matching assets: [ImmichAsset]) async -> [String] {
        guard !assets.isEmpty else { return [] }
        let wanted = Dictionary(assets.map { ($0.originalFileName.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })

        let options = PHFetchOptions()
        options.includeHiddenAssets = true
        let fetch = PHAsset.fetchAssets(with: options)

        var identifiers: [String] = []
        fetch.enumerateObjects { phAsset, _, _ in
            let names = PHAssetResource.assetResources(for: phAsset)
                .map { $0.originalFilename.lowercased() }
            for name in names {
                guard let asset = wanted[name] else { continue }
                if datesMatch(phAsset.creationDate, asset.takenAt) {
                    identifiers.append(phAsset.localIdentifier)
                    break
                }
            }
        }
        return identifiers
    }

    /// Deletes the given local photos. iOS shows a system confirmation.
    /// Returns true if the user confirmed the deletion.
    @discardableResult
    static func deleteAssets(localIdentifiers: [String]) async -> Bool {
        guard !localIdentifiers.isEmpty else { return false }
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: nil)
        guard fetch.count > 0 else { return false }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(fetch)
            }
            return true
        } catch {
            return false
        }
    }

    /// Capture times within a day of each other count as a match; if either is
    /// unknown, fall back to the filename match alone.
    private static func datesMatch(_ lhs: Date?, _ rhs: Date?) -> Bool {
        guard let lhs, let rhs else { return true }
        return abs(lhs.timeIntervalSince(rhs)) < 86_400
    }
}
