import SwiftUI

/// Generic finder screen: loads candidate assets, shows them in a selectable
/// grid, and moves the selection to the Immich trash.
struct CleanupSelectionGridView: View {
    let title: String
    let emptyDescription: String
    let headerNote: String?
    let preselectAll: Bool
    let client: ImmichClient
    let loadAssets: @MainActor () async throws -> [ImmichAsset]

    @Environment(StatsStore.self) private var stats

    @State private var assets: [ImmichAsset] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var selectedIDs: Set<String> = []
    @State private var isConfirmingTrash = false
    @State private var isShowingActionError = false
    @State private var actionError: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Searching…")
            } else if let loadError {
                ContentUnavailableView {
                    Label("Search failed", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Retry", action: retry)
                }
            } else if assets.isEmpty {
                ContentUnavailableView {
                    Label("Nothing found", systemImage: "checkmark.seal")
                } description: {
                    Text(emptyDescription)
                }
            } else {
                grid
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !assets.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(allSelected ? "Deselect All" : "Select All", action: toggleSelectAll)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !assets.isEmpty {
                trashButton
            }
        }
        .alert("Couldn't move to trash", isPresented: $isShowingActionError) {
        } message: {
            Text(actionError ?? "")
        }
        .task { await load() }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                ForEach(assets) { asset in
                    CleanupGridCellView(
                        asset: asset,
                        isSelected: selectedIDs.contains(asset.id),
                        caption: nil,
                        client: client,
                        toggle: { toggle(asset) }
                    )
                    .dragSelectCell(id: asset.id)
                }
            }
            .padding(.horizontal, 4)
        }
        .dragSelection(
            ids: assets.map(\.id),
            isSelected: { selectedIDs.contains($0) },
            onPaint: setSelected
        )
        .overlay(alignment: .top) {
            if let headerNote {
                Text(headerNote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.bar, in: .capsule)
                    .padding(.top, 4)
            }
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
            "Move \(selectedIDs.count) assets to the Immich trash?",
            isPresented: $isConfirmingTrash,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive, action: trashSelected)
        }
    }

    private var allSelected: Bool {
        selectedIDs.count == assets.count
    }

    private func toggle(_ asset: ImmichAsset) {
        if selectedIDs.contains(asset.id) {
            selectedIDs.remove(asset.id)
        } else {
            selectedIDs.insert(asset.id)
        }
    }

    private func setSelected(_ id: String, _ isSelected: Bool) {
        if isSelected {
            selectedIDs.insert(id)
        } else {
            selectedIDs.remove(id)
        }
    }

    private func toggleSelectAll() {
        selectedIDs = allSelected ? [] : Set(assets.map(\.id))
    }

    private func confirmTrash() {
        isConfirmingTrash = true
    }

    private func retry() {
        isLoading = true
        loadError = nil
        Task { await load() }
    }

    private func load() async {
        guard isLoading else { return }
        do {
            assets = try await loadAssets()
            if preselectAll {
                selectedIDs = Set(assets.map(\.id))
            }
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func trashSelected() {
        let ids = selectedIDs
        Task {
            do {
                try await client.trashAssets(ids: Array(ids))
                stats.recordTrashed(count: ids.count)
                assets.removeAll { ids.contains($0.id) }
                selectedIDs = []
            } catch {
                actionError = error.localizedDescription
                isShowingActionError = true
            }
        }
    }
}
