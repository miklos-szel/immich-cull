import SwiftUI

/// One photo or video card in the deck.
struct AssetCardView: View {
    let asset: ImmichAsset
    let client: ImmichClient
    let isTopCard: Bool
    var state: AssetCullState = .init()
    /// Called when the server has neither a preview nor the original.
    var onUnavailable: (() -> Void)?

    /// A Live Photo stays a still until tapped, then plays its paired movie —
    /// unlike a plain video, which plays as soon as it's the top card.
    @State private var isPlayingLive = false

    var body: some View {
        // The still is always drawn; for a top-card video the player is laid over
        // it. An AVPlayerLayer is transparent until it has frames, so the poster
        // shows through until playback starts — no spinner flash on the swap.
        RemoteImageView(
            url: client.thumbnailURL(assetID: asset.id),
            apiKey: client.apiKey,
            // Only stills can fall back to the original; a video's original is a
            // movie file, not something UIImage decodes.
            fallbackURL: asset.type == .image ? client.originalURL(assetID: asset.id) : nil,
            onUnavailable: onUnavailable
        )
        .overlay {
            if isTopCard, let videoURL = playableVideoURL {
                VideoCardView(url: videoURL, apiKey: client.apiKey)
            }
        }
        // A Live Photo plays its motion on tap and stops on the next tap; a plain
        // still or an already-autoplaying video ignores the tap.
        .onTapGesture { toggleLivePlayback() }
        .onChange(of: isTopCard) { _, isTop in
            if !isTop { isPlayingLive = false }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Letterboxing follows the theme — white in light mode, dark in dark —
        // so the card blends into the screen instead of sitting in a black box.
        .background(.background)
        .clipShape(.rect(cornerRadius: 16))
        // Labelled before the overlay is attached, so the badges stay a
        // separate accessibility element instead of being folded into the
        // card's own label — which also keeps them queryable from UI tests.
        .accessibilityLabel(asset.originalFileName)
        // Top *leading*: the trash marker owns the top centre of the deck.
        .overlay(alignment: .topLeading) {
            AssetStateBadgesView(state: state)
                .padding(12)
        }
        .overlay(alignment: .bottomLeading) {
            MediaKindBadgeView(asset: asset)
        }
    }

    /// The movie to lay over the still: a plain video's own stream, or a tapped
    /// Live Photo's paired motion. `nil` means show the still alone.
    private var playableVideoURL: URL? {
        if asset.type == .video {
            return client.videoPlaybackURL(assetID: asset.id)
        }
        if asset.isLivePhoto, isPlayingLive, let motionID = asset.livePhotoVideoId {
            return client.videoPlaybackURL(assetID: motionID)
        }
        return nil
    }

    private func toggleLivePlayback() {
        guard isTopCard, asset.isLivePhoto else { return }
        isPlayingLive.toggle()
    }
}
