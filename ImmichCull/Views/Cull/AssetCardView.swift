import SwiftUI

/// One photo or video card in the deck.
struct AssetCardView: View {
    let asset: ImmichAsset
    let client: ImmichClient
    let isTopCard: Bool
    /// Called when the server has neither a preview nor the original.
    var onUnavailable: (() -> Void)?

    var body: some View {
        Group {
            if asset.type == .video && isTopCard {
                VideoCardView(url: client.videoPlaybackURL(assetID: asset.id), apiKey: client.apiKey)
            } else {
                RemoteImageView(
                    url: client.thumbnailURL(assetID: asset.id),
                    apiKey: client.apiKey,
                    // Only stills can fall back to the original; a video's
                    // original is a movie file, not something UIImage decodes.
                    fallbackURL: asset.type == .image ? client.originalURL(assetID: asset.id) : nil,
                    onUnavailable: onUnavailable
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Letterboxing follows the theme — white in light mode, dark in dark —
        // so the card blends into the screen instead of sitting in a black box.
        .background(.background)
        .clipShape(.rect(cornerRadius: 16))
        .accessibilityLabel(asset.originalFileName)
    }
}
