import SwiftUI

/// Small status pills for the state a session already knows about an asset:
/// favorited, in the destination album, or already culled.
struct AssetStateBadgesView: View {
    let state: AssetCullState

    var body: some View {
        HStack(spacing: 4) {
            if state.isFavorite {
                badge("heart.fill", tint: .pink)
            }
            if state.isInDestinationAlbum {
                badge("rectangle.stack.fill", tint: .blue)
            }
            if state.isChecked {
                badge("checkmark.seal.fill", tint: .green)
            }
        }
    }

    private func badge(_ systemImage: String, tint: Color) -> some View {
        Image(systemName: systemImage)
            .font(.caption2)
            .foregroundStyle(.white)
            .padding(4)
            .background(tint, in: .circle)
            .shadow(radius: 1)
    }
}

/// A corner badge marking a video (with the paired-movie note for Live Photos).
struct MediaKindBadgeView: View {
    let asset: ImmichAsset

    var body: some View {
        if asset.type == .video {
            Image(systemName: "video.fill")
                .font(.caption2)
                .foregroundStyle(.white)
                .padding(4)
                .background(.black.opacity(0.5), in: .capsule)
        } else if asset.isLivePhoto {
            Image(systemName: "livephoto")
                .font(.caption2)
                .foregroundStyle(.white)
                .padding(4)
                .background(.black.opacity(0.5), in: .capsule)
        }
    }
}
