import Photos

/// Matches Immich assets to local photos and deletes them.
///
/// A wrong match deletes a photo the user never chose, so matching errs toward
/// missing: an asset matches either exactly (its `deviceAssetId` is this
/// library's local identifier and the filename agrees) or by filename *and* a
/// capture time that lines up. An asset with no usable capture time never
/// matches on filename alone — `IMG_0001.JPG` recurs across devices and years.
enum PhotoLibraryService {
    /// Timestamps are compared as instants, but Immich's can be off by a whole
    /// timezone offset when EXIF carried no zone. Offsets come in 15-minute
    /// steps up to ±14h, so a difference within `slack` of such a step still
    /// matches — far tighter than the old blanket ±24h window.
    private static let slack: TimeInterval = 120
    private static let offsetStep: TimeInterval = 15 * 60
    private static let maxOffset: TimeInterval = 14 * 3600

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

    /// Local identifiers of the photos matching `assets`, for later deletion.
    ///
    /// Speed matters too: this runs before the system delete confirmation
    /// appears. The fuzzy pass fetches only the capture-date window the wanted
    /// assets span, and checks the cheap date before the per-asset I/O of
    /// `PHAssetResource.assetResources`.
    static func localIdentifiers(matching assets: [ImmichAsset]) async -> [String] {
        guard !assets.isEmpty else { return [] }

        var identifiers: [String] = []
        var remaining: [ImmichAsset] = []

        // Exact pass: photos uploaded from this device carry its identifier.
        let candidates = assets.compactMap(\.deviceAssetId)
        var exact: [String: PHAsset] = [:]
        if !candidates.isEmpty {
            let fetch = PHAsset.fetchAssets(withLocalIdentifiers: candidates, options: nil)
            fetch.enumerateObjects { phAsset, _, _ in exact[phAsset.localIdentifier] = phAsset }
        }
        for asset in assets {
            if let id = asset.deviceAssetId, let phAsset = exact[id],
               filenames(of: phAsset).contains(asset.originalFileName.lowercased()) {
                identifiers.append(id)
            } else {
                remaining.append(asset)
            }
        }

        // Fuzzy pass: filename plus capture time, for the rest that have one.
        let dated = remaining.filter { captureDate(of: $0) != nil }
        guard let window = captureDateWindow(for: dated) else { return identifiers }
        let wanted = Dictionary(grouping: dated) { $0.originalFileName.lowercased() }
        let alreadyMatched = Set(identifiers)

        let options = PHFetchOptions()
        options.includeHiddenAssets = true
        options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate <= %@",
                                        window.start as NSDate, window.end as NSDate)
        PHAsset.fetchAssets(with: options).enumerateObjects { phAsset, _, _ in
            guard !alreadyMatched.contains(phAsset.localIdentifier),
                  dated.contains(where: { datesMatch(phAsset.creationDate, captureDate(of: $0)) }) else { return }
            for name in filenames(of: phAsset) {
                guard let matches = wanted[name] else { continue }
                if matches.contains(where: { datesMatch(phAsset.creationDate, captureDate(of: $0)) }) {
                    identifiers.append(phAsset.localIdentifier)
                    break
                }
            }
        }
        return identifiers
    }

    /// Deletes the given local photos. The system shows a confirmation.
    /// Returns true if the user confirmed and the deletion went through.
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

    // MARK: Matching helpers

    private static func filenames(of phAsset: PHAsset) -> [String] {
        PHAssetResource.assetResources(for: phAsset).map { $0.originalFilename.lowercased() }
    }

    /// The instant to compare against `PHAsset.creationDate`: `fileCreatedAt`,
    /// else the wall-clock `localDateTime` (whose offset error the timezone
    /// tolerance in `datesMatch` absorbs).
    private static func captureDate(of asset: ImmichAsset) -> Date? {
        asset.createdAt ?? asset.takenAt
    }

    private static func captureDateWindow(for assets: [ImmichAsset]) -> (start: Date, end: Date)? {
        let dates = assets.compactMap(captureDate)
        guard let earliest = dates.min(), let latest = dates.max() else { return nil }
        let pad = maxOffset + slack
        return (earliest.addingTimeInterval(-pad), latest.addingTimeInterval(pad))
    }

    /// Same instant, or the same instant shifted by a plausible timezone
    /// offset. A missing date on either side is *not* a match.
    static func datesMatch(_ lhs: Date?, _ rhs: Date?) -> Bool {
        guard let lhs, let rhs else { return false }
        let difference = abs(lhs.timeIntervalSince(rhs))
        guard difference <= maxOffset + slack else { return false }
        let remainder = difference.truncatingRemainder(dividingBy: offsetStep)
        return remainder <= slack || remainder >= offsetStep - slack
    }
}
