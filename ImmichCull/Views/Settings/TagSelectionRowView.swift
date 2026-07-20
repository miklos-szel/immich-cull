import SwiftUI

/// One checkmark row in `TagSelectionView`.
struct TagSelectionRowView: View {
    let name: String
    let isSelected: Bool
    /// Selected, but the server no longer lists this tag.
    var isMissing = false
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .foregroundStyle(.primary)
                    if isMissing {
                        Text("Not on this server")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tagRow")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
