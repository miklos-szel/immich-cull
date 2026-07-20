import Photos

/// Matches Immich assets to local iPhone photos and deletes them.
/// Matching is best-effort: by original filename, narrowed by capture date.
enum PhotoLibraryService {
    /// How far apart two capture times can be and still count as the same
    /// photo. Immich and the local library disagree by timezone often enough
    /// that anything tighter produces false misses.
    private static let dateTolerance: TimeInterval = 86_400

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
    ///
    /// Speed matters here, not just tidiness: this runs before the system
    /// delete confirmation appears, so a slow scan means the user is asked
    /// minutes after they acted, long after they've moved on.
    ///
    /// Two things keep it quick. The fetch is narrowed to the capture-date
    /// window the wanted assets actually span, instead of the whole library.
    /// And within it, the cheap date comparison runs *before*
    /// `PHAssetResource.assetResources`, which costs per-asset I/O — checking
    /// every photo's resources first was the real expense.
    static func localIdentifiers(matching assets: [ImmichAsset]) async -> [String] {
        guard !assets.isEmpty else { return [] }

        // Grouped, not a plain dictionary: two photos can share a filename
        // (IMG_0001.jpg from two devices) and the capture date is what tells
        // them apart. Keying by name alone silently dropped one of them.
        let wanted = Dictionary(grouping: assets) { $0.originalFileName.lowercased() }

        let options = PHFetchOptions()
        options.includeHiddenAssets = true
        if let window = captureDateWindow(for: assets) {
            options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate <= %@",
                                            window.start as NSDate, window.end as NSDate)
        }
        let fetch = PHAsset.fetchAssets(with: options)

        var identifiers: [String] = []
        fetch.enumerateObjects { phAsset, _, _ in
            // Reject on date before touching resources, where possible.
            let candidatesByDate = assets.contains { datesMatch(phAsset.creationDate, $0.takenAt) }
            guard candidatesByDate else { return }

            let names = PHAssetResource.assetResources(for: phAsset)
                .map { $0.originalFilename.lowercased() }
            for name in names {
                guard let matches = wanted[name] else { continue }
                if matches.contains(where: { datesMatch(phAsset.creationDate, $0.takenAt) }) {
                    identifiers.append(phAsset.localIdentifier)
                    break
                }
            }
        }
        return identifiers
    }

    /// The span of capture dates to search, padded by the same tolerance
    /// `datesMatch` allows. Nil when any asset has no capture date — those
    /// match on filename alone, so the search can't be narrowed safely.
    private static func captureDateWindow(for assets: [ImmichAsset]) -> (start: Date, end: Date)? {
        var earliest: Date?
        var latest: Date?
        for asset in assets {
            guard let taken = asset.takenAt else { return nil }
            earliest = min(earliest ?? taken, taken)
            latest = max(latest ?? taken, taken)
        }
        guard let earliest, let latest else { return nil }
        return (earliest.addingTimeInterval(-dateTolerance), latest.addingTimeInterval(dateTolerance))
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
        return abs(lhs.timeIntervalSince(rhs)) < dateTolerance
    }
}
