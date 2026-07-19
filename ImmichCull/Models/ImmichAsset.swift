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

    /// Immich sends ISO 8601 with fractional seconds, e.g. "2024-01-01T12:30:00.000Z".
    var takenAt: Date? {
        try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(localDateTime)
    }
}
