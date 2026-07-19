import SwiftUI

/// Thumbnail overview of everything still to review, opened from the title on
/// the cull screen. Tap a photo to continue from it, or switch to selection
/// mode to trash several at once.
struct CullGridView: View {
    let session: CullSession
    let client: ImmichClient
    let title: String

    @Environment(\.dismiss) private var dismiss

    @State private var isSelecting = false
    @State private var selectedIDs: Set<String> = []
    @State private var isConfirmingTrash = false

    var body: some View {
        NavigationStack {
            Group {
                if session.queue.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing left", systemImage: "checkmark.seal")
                    } description: {
                        Text("Every photo here has been reviewed.")
                    }
                } else {
                    grid
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done", action: dismiss.callAsFunction)
                }
                if !session.queue.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(isSelecting ? "Cancel" : "Select", action: toggleSelectionMode)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isSelecting {
                    trashButton
                }
            }
        }
    }

    private var grid: some View {
        ScrollView {
            Text(isSelecting
                 ? "Select photos to move to the trash."
                 : "Tap a photo to continue culling from it.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.top, 4)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                ForEach(session.queue) { asset in
                    CleanupGridCellView(
                        asset: asset,
                        isSelected: selectedIDs.contains(asset.id),
                        caption: nil,
                        client: client,
                        toggle: { handleTap(asset) }
                    )
                    .dragSelectCell(id: asset.id)
                }
            }
            .padding(.horizontal, 4)
        }
        .dragSelection(
            isSelected: { selectedIDs.contains($0) },
            onPaint: setSelected
        )
    }

    private var trashButton: some View {
        Button(role: .destructive, action: confirmTrash) {
            Label("Move \(selectedIDs.count) to Trash", systemImage: "trash")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(selectedIDs.isEmpty)
        .padding()
        .background(.bar)
        .confirmationDialog(
            trashDialogTitle,
            isPresented: $isConfirmingTrash,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive, action: trashSelected)
        }
    }

    private var trashDialogTitle: String {
        selectedIDs.count == 1
            ? String(localized: "Move 1 photo to the Immich trash?")
            : String(localized: "Move \(selectedIDs.count) photos to the Immich trash?")
    }

    private func handleTap(_ asset: ImmichAsset) {
        if isSelecting {
            if selectedIDs.contains(asset.id) {
                selectedIDs.remove(asset.id)
            } else {
                selectedIDs.insert(asset.id)
            }
        } else {
            session.jump(to: asset)
            dismiss()
        }
    }

    /// Painting is also the way into selection mode — unlike the toolbar button,
    /// entering this way must keep what the drag has already selected.
    private func setSelected(_ id: String, _ isSelected: Bool) {
        isSelecting = true
        if isSelected {
            selectedIDs.insert(id)
        } else {
            selectedIDs.remove(id)
        }
    }

    private func toggleSelectionMode() {
        isSelecting.toggle()
        selectedIDs = []
    }

    private func confirmTrash() {
        isConfirmingTrash = true
    }

    private func trashSelected() {
        let assets = session.queue.filter { selectedIDs.contains($0.id) }
        session.trashSelected(assets)
        selectedIDs = []
        isSelecting = false
        if session.queue.isEmpty {
            dismiss()
        }
    }
}
