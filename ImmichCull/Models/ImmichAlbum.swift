import Foundation

struct ImmichAlbum: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let albumName: String
    let assetCount: Int
    let albumThumbnailAssetId: String?
}
