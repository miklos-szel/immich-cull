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
    @State private var pageIndex = 0

    private static let hintHeight: CGFloat = 20

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

    /// Paged, not scrolled. A static page gives a selection drag no scroll view
    /// to wrestle for the touch, so nothing slides out from under the finger —
    /// which is what made drag-select unreliable while this was a `ScrollView`.
    private var grid: some View {
        GeometryReader { geometry in
            let pages = pages(fitting: geometry.size)
            VStack(spacing: 4) {
                hint(pageCount: pages.count)
                    .frame(height: Self.hintHeight)
                TabView(selection: $pageIndex) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, assets in
                        CullGridPageView(
                            assets: assets,
                            selectedIDs: selectedIDs,
                            columns: CullGridMetrics.columns,
                            client: client,
                            onTap: handleTap
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .dragSelection(
                    ids: session.queue.map(\.id),
                    isSelected: { selectedIDs.contains($0) },
                    onPaint: setSelected
                )
            }
        }
    }

    private func hint(pageCount: Int) -> some View {
        HStack {
            Text(isSelecting
                 ? "Press and drag to select. Swipe sideways for more."
                 : "Tap a photo to continue culling from it.")
            Spacer()
            if pageCount > 1 {
                Text("\(pageIndex + 1) / \(pageCount)").monospacedDigit()
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
    }

    private func pages(fitting size: CGSize) -> [[ImmichAsset]] {
        let available = CGSize(width: size.width, height: size.height - Self.hintHeight)
        let pageSize = CullGridMetrics.pageSize(fitting: available)
        let queue = session.queue
        return stride(from: 0, to: queue.count, by: pageSize).map {
            Array(queue[$0..<min($0 + pageSize, queue.count)])
        }
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
