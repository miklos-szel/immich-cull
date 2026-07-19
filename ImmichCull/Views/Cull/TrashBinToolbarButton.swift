import SwiftUI

/// Trash-bin toolbar button with a red badge showing how many items are in the Immich trash.
struct TrashBinToolbarButton: View {
    let count: Int
    /// Distinct per screen: the cull deck presents over Home, so both buttons are
    /// in the hierarchy at once and UI tests need to tell them apart.
    var identifier: String = "trashBinButton"
    let action: () -> Void

    /// Square, so the glyph has the same slack on every side and the badge has
    /// a corner to sit in without pushing anything around.
    private static let box: CGFloat = 38

    var body: some View {
        Button(action: action) {
            // A fixed square box, with the badge as an overlay that can't affect
            // layout: the glyph is then centred by construction, badge or no
            // badge, so it lines up with its plain neighbours in the toolbar.
            // The badge lives inside the box for the same reason as before —
            // offsetting it outside the button's bounds gets it clipped.
            Image(systemName: "trash")
                .frame(width: Self.box, height: Self.box)
                .overlay(alignment: .topTrailing) {
                    if count > 0 {
                        Text(count, format: .number)
                            .font(.system(size: 10, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(.red, in: .capsule)
                    }
                }
        }
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier(identifier)
    }

    private var accessibilityText: String {
        switch count {
        case 0: String(localized: "Trash bin")
        case 1: String(localized: "Trash bin, 1 item")
        default: String(localized: "Trash bin, \(count) items")
        }
    }
}
