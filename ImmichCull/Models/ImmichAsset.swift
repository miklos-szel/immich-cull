import Foundation

struct ImmichAsset: Codable, Identifiable, Hashable, Sendable {
    // Only fields the app uses; notably `duration` changed type across Immich
    // versions (string → milliseconds int), so it is deliberately not decoded.
    let id: String
    let type: AssetType
    let originalFileName: String
    let localDateTime: String
    let isFavorite: Bool?
    let isTrashed: Bool?
    let originalMimeType: String?
    let exifInfo: AssetExif?
    let tags: [ImmichTag]?
    /// Non-nil when this still is a Live Photo — it points at the paired video.
    let livePhotoVideoId: String?
    /// The uploading device's own ID for the file. The Immich mobile app sets it
    /// to the `PHAsset.localIdentifier`, which makes it an exact local match on
    /// the phone that uploaded it (and meaningless anywhere else).
    let deviceAssetId: String?
    let deviceId: String?
    /// Capture time as a real UTC instant — unlike `localDateTime`, which is
    /// wall-clock time mislabelled with a `Z`.
    let fileCreatedAt: String?

    /// Immich sends ISO 8601 with fractional seconds, e.g. "2024-01-01T12:30:00.000Z".
    var takenAt: Date? {
        try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(localDateTime)
    }

    /// `fileCreatedAt` parsed; the instant to compare against `PHAsset.creationDate`.
    var createdAt: Date? {
        guard let fileCreatedAt else { return nil }
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(fileCreatedAt) {
            return date
        }
        return try? Date.ISO8601FormatStyle().parse(fileCreatedAt)
    }

    var isLivePhoto: Bool { livePhotoVideoId != nil }

    /// The asset's own ID plus, for a Live Photo, its paired movie — so trashing
    /// or restoring the still takes the `.mov` with it instead of orphaning it.
    /// A plain asset is just itself.
    var idsIncludingLivePhotoPair: [String] {
        if let livePhotoVideoId { return [id, livePhotoVideoId] }
        return [id]
    }
}

extension Sequence where Element == ImmichAsset {
    /// Flattened IDs of these assets and any paired Live Photo movies, ready for
    /// a bulk trash / restore call.
    var idsIncludingLivePhotoPairs: [String] {
        flatMap(\.idsIncludingLivePhotoPair)
    }
}
