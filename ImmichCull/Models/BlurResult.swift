import Foundation

struct BlurResult: Identifiable, Sendable {
    let asset: ImmichAsset
    /// Variance of the Laplacian — lower means blurrier.
    let score: Double

    var id: String { asset.id }
}
