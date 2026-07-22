import SwiftUI

/// One square thumbnail in the browse grid, with selection ring and badges.
///
/// The square is defined by the background rectangle (which takes the column
/// width); the image is an *overlay* so its `.fill` scaling can't push the cell
/// wider than its column — that overflow made neighbouring thumbnails overlap.
struct GridCellView: View {
    let asset: ImmichAsset
    let client: ImmichClient?
    let apiKey: String
    let state: AssetCullState
    let isSelected: Bool
    let isCursor: Bool

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .quaternarySystemFill))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let client {
                    RemoteImageMacView(
                        url: client.thumbnailURL(assetID: asset.id, size: "thumbnail"),
                        apiKey: apiKey,
                        contentMode: .fill,
                        fallbackURL: client.originalURL(assetID: asset.id))
                }
            }
            .clipShape(.rect(cornerRadius: 6))
            .overlay(alignment: .topLeading) {
                AssetStateBadgesView(state: state).padding(4)
            }
            .overlay(alignment: .bottomLeading) {
                MediaKindBadgeView(asset: asset).padding(4)
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, isSelected ? Color.accentColor : Color.black.opacity(0.35))
                    .padding(4)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : (isCursor ? Color.secondary : .clear),
                            lineWidth: isSelected ? 3 : 2)
            }
            .contentShape(.rect)
    }
}
