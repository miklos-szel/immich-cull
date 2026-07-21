import SwiftUI

/// Thumbnail overview of everything still to review, opened from the title on
/// the cull screen. A continuous lazy grid (no paging): tap the cull icon on a
/// photo to continue the run from it, or press-and-drag to trash several at once.
struct CullGridView: View {
    let session: CullSession
    let client: ImmichClient
    let title: String

    @Environment(\.dismiss) private var dismiss

    @State private var selectedIDs: Set<String> = []
    @State private var isConfirmingTrash = false

    /// A stable display order for the overview. The live queue is rotated by
    /// `jump(to:)`, so reading it directly reshuffles the grid every time you dip
    /// into a photo and come back. Sorting by capture date (newest first — the
    /// fetch order), with an ID tiebreaker so equal dates can't swap, keeps it put
    /// without touching the queue the session actually culls from.
    private var orderedAssets: [ImmichAsset] {
        session.queue.sorted {
            let a = $0.takenAt ?? .distantPast
            let b = $1.takenAt ?? .distantPast
            return a != b ? a > b : $0.id < $1.id
        }
    }

    private func allSelected(among assets: [ImmichAsset]) -> Bool {
        !assets.isEmpty && selectedIDs.count == assets.count
    }

    var body: some View {
        // Sort once per render and thread the result through every consumer,
        // rather than re-sorting the queue on each read of `orderedAssets`.
        let assets = orderedAssets
        NavigationStack {
            Group {
                if assets.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing left", systemImage: "checkmark.seal")
                    } description: {
                        Text("Every photo here has been reviewed.")
                    }
                } else {
                    grid(assets: assets)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done", action: dismiss.callAsFunction)
                }
                if !assets.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        // Select exactly one photo to continue the run from it.
                        Button("Continue Here", systemImage: "play.rectangle", action: continueFromSelection)
                            .disabled(selectedIDs.count != 1)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(allSelected(among: assets) ? "Deselect All" : "Select All") {
                            toggleSelectAll(assets)
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !selectedIDs.isEmpty {
                    trashButton
                }
            }
        }
    }

    private func grid(assets: [ImmichAsset]) -> some View {
        ScrollView {
            hint
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                ForEach(assets) { asset in
                    CleanupGridCellView(
                        asset: asset,
                        isSelected: selectedIDs.contains(asset.id),
                        caption: nil,
                        state: session.state(for: asset),
                        client: client,
                        toggle: { toggleSelect(asset) }
                    )
                    .dragSelectCell(id: asset.id)
                }
            }
            .padding(.horizontal, 4)
        }
        .dragSelection(
            ids: assets.map(\.id),
            autoScroll: true,
            isSelected: { selectedIDs.contains($0) },
            onPaint: setSelected
        )
    }

    private var hint: Text {
        Text("Press and drag to select. Pick one photo, then Continue Here to cull from it.")
    }

    private var trashButton: some View {
        Button(role: .destructive, action: confirmTrash) {
            Label("Move \(selectedIDs.count) to Trash", systemImage: "trash")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
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

    /// Continue the run from the single selected photo.
    private func continueFromSelection() {
        guard selectedIDs.count == 1, let id = selectedIDs.first,
              let asset = session.queue.first(where: { $0.id == id }) else { return }
        session.jump(to: asset)
        dismiss()
    }

    private func toggleSelect(_ asset: ImmichAsset) {
        setSelected(asset.id, !selectedIDs.contains(asset.id))
    }

    private func setSelected(_ id: String, _ isSelected: Bool) {
        if isSelected {
            selectedIDs.insert(id)
        } else {
            selectedIDs.remove(id)
        }
    }

    private func toggleSelectAll(_ assets: [ImmichAsset]) {
        selectedIDs = allSelected(among: assets) ? [] : Set(assets.map(\.id))
    }

    private func confirmTrash() {
        isConfirmingTrash = true
    }

    private func trashSelected() {
        let assets = session.queue.filter { selectedIDs.contains($0.id) }
        session.trashSelected(assets)
        selectedIDs = []
        if session.queue.isEmpty {
            dismiss()
        }
    }
}
