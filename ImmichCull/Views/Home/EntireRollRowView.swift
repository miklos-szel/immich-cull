import SwiftUI

/// The "cull everything" option shown at the top of the album list.
struct EntireRollRowView: View {
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                Image(systemName: "photo.stack")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 56, height: 56)
                    .background(.quaternary, in: .rect(cornerRadius: 8))
                VStack(alignment: .leading) {
                    Text("Entire Roll")
                        .foregroundStyle(.primary)
                    Text("All photos and videos")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .imageScale(.large)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
