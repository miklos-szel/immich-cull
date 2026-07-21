import SwiftUI

/// Small corner badge marking an asset as a video or a Live Photo; a plain still
/// shows nothing. The two are mutually exclusive — a Live Photo is a `.image`,
/// a video is a `.video` — so at most one ever renders.
struct MediaKindBadgeView: View {
    let asset: ImmichAsset
    /// Grid cells are tiny, so they use a lighter-weight version.
    var compact = false

    var body: some View {
        if asset.type == .video {
            badge {
                Image(systemName: "video.fill")
                    .accessibilityLabel("Video")
            }
        } else if asset.isLivePhoto {
            badge {
                Label("LIVE", systemImage: "livephoto")
                    .labelStyle(.titleAndIcon)
                    .accessibilityLabel("Live Photo")
            }
        }
    }

    private func badge<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .font(compact ? .system(size: 9, weight: .bold) : .caption.bold())
            .foregroundStyle(.white)
            .shadow(radius: 2)
            .padding(.horizontal, compact ? 4 : 6)
            .padding(.vertical, compact ? 2 : 3)
            .background(.black.opacity(0.35), in: .capsule)
            .padding(compact ? 4 : 12)
    }
}
