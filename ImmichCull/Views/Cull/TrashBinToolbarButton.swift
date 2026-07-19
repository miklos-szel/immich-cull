import SwiftUI

/// Trash-bin toolbar button with a red badge showing how many items are in the Immich trash.
struct TrashBinToolbarButton: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // The badge sits inside the button's own bounds — insetting the
            // glyph instead of offsetting the badge keeps it from being clipped.
            ZStack(alignment: .topTrailing) {
                Image(systemName: "trash")
                    .padding(.top, 7)
                    .padding(.trailing, 9)
                if count > 0 {
                    Text(count, format: .number)
                        .font(.system(size: 11, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 17, minHeight: 17)
                        .background(.red, in: .capsule)
                }
            }
            .fixedSize()
        }
        .accessibilityLabel(count > 0 ? "Trash bin, \(count) items" : "Trash bin")
        .accessibilityIdentifier("trashBinButton")
    }
}
