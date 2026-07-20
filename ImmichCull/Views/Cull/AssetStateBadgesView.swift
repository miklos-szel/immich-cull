import SwiftUI

/// Shows what has already been done to an asset: culled, favorited, or added to
/// the destination album. Without it, a photo you already dealt with looks
/// exactly like a fresh one.
struct AssetStateBadgesView: View {
    let state: AssetCullState
    /// Smaller, icon-only treatment for grid thumbnails, where a word of text
    /// would cover most of the cell.
    var compact = false

    var body: some View {
        if !state.isEmpty {
            HStack(spacing: compact ? 3 : 6) {
                if state.isChecked {
                    if compact {
                        Image(systemName: "checkmark.seal.fill")
                    } else {
                        Text("Culled")
                            .font(.caption.weight(.semibold))
                            .textCase(.uppercase)
                    }
                }
                if state.isFavorite {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.pink)
                }
                if state.isInDestinationAlbum {
                    Image(systemName: "checkmark.rectangle.stack.fill")
                }
            }
            .font(compact ? .caption2 : .caption)
            .padding(.horizontal, compact ? 5 : 8)
            .padding(.vertical, compact ? 2 : 4)
            .background(.thinMaterial, in: .capsule)
            // The deck reads drags off the card and the grid cell is a button;
            // an overlay that takes touches breaks both.
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("assetStateBadges")
            .accessibilityLabel(accessibilityLabel)
        }
    }

    private var accessibilityLabel: String {
        var parts: [String] = []
        if state.isChecked { parts.append(String(localized: "Culled")) }
        if state.isFavorite { parts.append(String(localized: "Favorite")) }
        if state.isInDestinationAlbum { parts.append(String(localized: "In album")) }
        return parts.joined(separator: ", ")
    }
}
