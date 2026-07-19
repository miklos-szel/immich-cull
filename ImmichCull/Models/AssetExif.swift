import Foundation

/// Subset of EXIF data used by the cleanup heuristics.
struct AssetExif: Codable, Hashable, Sendable {
    let make: String?
    let model: String?
}
