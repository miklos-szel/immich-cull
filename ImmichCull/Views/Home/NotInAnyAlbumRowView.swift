import SwiftUI

/// The "cull the unsorted pile" option: every asset that belongs to no album.
/// Sits under Entire Roll and shares its radio selection.
struct NotInAnyAlbumRowView: View {
    /// Opens the full-screen grid for assets in no album.
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Image(systemName: "questionmark.folder")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 56, height: 56)
                    .background(.quaternary, in: .rect(cornerRadius: 8))
                VStack(alignment: .leading) {
                    Text("Not in Any Album")
                        .foregroundStyle(.primary)
                    Text("Photos and videos you haven't sorted")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .font(.footnote.weight(.semibold))
                    .accessibilityHidden(true)
            }
        }
    }
}
