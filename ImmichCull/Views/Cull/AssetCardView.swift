import SwiftUI

/// One photo or video card in the deck.
struct AssetCardView: View {
    let asset: ImmichAsset
    let client: ImmichClient
    let isTopCard: Bool

    var body: some View {
        Group {
            if asset.type == .video && isTopCard {
                VideoCardView(url: client.videoPlaybackURL(assetID: asset.id), apiKey: client.apiKey)
            } else {
                RemoteImageView(url: client.thumbnailURL(assetID: asset.id), apiKey: client.apiKey)
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
