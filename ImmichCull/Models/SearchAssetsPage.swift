import Foundation

struct SearchAssetsPage: Codable, Sendable {
    let items: [ImmichAsset]
    let nextPage: String?
}
