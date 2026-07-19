import Foundation

/// Response of `GET /assets/statistics`.
struct AssetStats: Codable, Sendable {
    let images: Int
    let total: Int
    let videos: Int
}
