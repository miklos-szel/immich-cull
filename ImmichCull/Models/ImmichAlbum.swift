import Foundation

struct ImmichAlbum: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let albumName: String
    let assetCount: Int
    let albumThumbnailAssetId: String?
    // All optional: older Immich versions may omit them, and an album with no
    // assets has no start/end date at all.
    let startDate: String?
    let endDate: String?
    let updatedAt: String?

    /// The date the album sorts by. Prefers when the album's photos were taken
    /// over when the album record was last touched, so renaming an old album
    /// doesn't shove it to the top of the list.
    var sortDate: Date? {
        for candidate in [endDate, startDate, updatedAt] {
            if let candidate, let date = Self.parse(candidate) { return date }
        }
        return nil
    }

    /// Immich sends ISO 8601 with fractional seconds, e.g. "2024-01-01T12:30:00.000Z",
    /// but not every field on every version carries the fractional part — and a
    /// parse failure here silently drops the album to the bottom of the list.
    private static func parse(_ value: String) -> Date? {
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value) {
            return date
        }
        return try? Date.ISO8601FormatStyle().parse(value)
    }
}
