import SwiftUI

/// One selectable thumbnail in a cleanup grid; selected means "will be trashed".
struct CleanupGridCellView: View {
    let asset: ImmichAsset
    let isSelected: Bool
    let caption: String?
    var selectionTint: Color = .red
    let client: ImmichClient
    /// Left empty by grids that use `dragSelection`: that modifier claims the
    /// touch for its paint gesture and handles the tap itself, so wiring the
    /// button up too would toggle twice for one tap and cancel itself out.
    var toggle: () -> Void = {}

    var body: some View {
        Button(action: toggle) {
            VStack(spacing: 2) {
                thumbnail
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(asset.originalFileName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var thumbnail: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                RemoteImageView(
                    url: client.thumbnailURL(assetID: asset.id, size: "thumbnail"),
                    apiKey: client.apiKey,
                    contentMode: .fill
                )
            }
            .clipShape(.rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(selectionTint, lineWidth: isSelected ? 3 : 0)
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? selectionTint : .white)
                    .shadow(radius: 2)
                    .padding(6)
                    .accessibilityHidden(true)
            }
    }
}
