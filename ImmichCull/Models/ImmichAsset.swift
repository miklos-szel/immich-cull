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

    /// Immich sends ISO 8601 with fractional seconds, e.g. "2024-01-01T12:30:00.000Z".
    var takenAt: Date? {
        try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(localDateTime)
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
