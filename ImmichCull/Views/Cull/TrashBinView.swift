import SwiftUI

/// Browses the Immich trash and restores selected assets.
struct TrashBinView: View {
    let client: ImmichClient
    /// Reports permanently deleted asset IDs so the caller can drop them from
    /// any state that assumed they were still restorable.
    var onPermanentDelete: (Set<String>) -> Void = { _ in }

    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var assets: [ImmichAsset] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var selectedIDs: Set<String> = []
    @State private var isShowingActionError = false
    @State private var actionError: String?
    @State private var isConfirmingDelete = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading trash…")
                } else if let loadError {
                    ContentUnavailableView {
                        Label("Couldn't load trash", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(loadError)
                    } actions: {
                        Button("Retry", action: retry)
                    }
                } else if assets.isEmpty {
                    ContentUnavailableView {
                        Label("Trash is empty", systemImage: "trash.slash")
                    } description: {
                        Text("Nothing has been moved to the Immich trash.")
                    }
                } else {
                    grid
                }
            }
            .navigationTitle("Immich Trash")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done", action: dismiss.callAsFunction)
                }
                if !assets.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(allSelected ? "Deselect All" : "Select All", action: toggleSelectAll)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !assets.isEmpty {
                    actionBar
                }
            }
            .alert("Something went wrong", isPresented: $isShowingActionError) {
            } message: {
                Text(actionError ?? "")
            }
            .task { await load() }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                ForEach(assets) { asset in
                    CleanupGridCellView(
                        asset: asset,
                        isSelected: selectedIDs.contains(asset.id),
                        caption: nil,
                        selectionTint: .green,
                        client: client,
                        toggle: { toggle(asset) }
                    )
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button(action: restoreSelected) {
                Label("Restore \(selectedIDs.count)", systemImage: "arrow.uturn.backward")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            Button(role: .destructive, action: confirmDelete) {
                Label("Delete \(selectedIDs.count)", systemImage: "trash.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .confirmationDialog(
                deleteDialogTitle,
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete Permanently", role: .destructive, action: deleteSelectedPermanently)
            } message: {
                Text("This cannot be undone.")
            }
        }
        .controlSize(.large)
        .disabled(selectedIDs.isEmpty)
        .padding()
        .background(.bar)
    }

    private var deleteDialogTitle: String {
        String(localized: "Permanently delete \(selectedIDs.count) from Immich and this device?")
    }

    private var allSelected: Bool {
        !assets.isEmpty && selectedIDs.count == assets.count
    }

    private func toggle(_ asset: ImmichAsset) {
        if selectedIDs.contains(asset.id) {
            selectedIDs.remove(asset.id)
        } else {
            selectedIDs.insert(asset.id)
        }
    }

    private func toggleSelectAll() {
        selectedIDs = allSelected ? [] : Set(assets.map(\.id))
    }

    private func retry() {
        isLoading = true
        loadError = nil
        Task { await load() }
    }

    private func load() async {
        do {
            assets = try await client.trashedAssets()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func restoreSelected() {
        let ids = selectedIDs
        Task {
            do {
                try await client.restoreAssets(ids: Array(ids))
                assets.removeAll { ids.contains($0.id) }
                selectedIDs = []
            } catch {
                actionError = error.localizedDescription
                isShowingActionError = true
            }
        }
    }

    private func confirmDelete() {
        isConfirmingDelete = true
    }

    private func deleteSelectedPermanently() {
        let ids = selectedIDs
        let toDelete = assets.filter { ids.contains($0.id) }
        Task {
            do {
                try await client.permanentlyDeleteAssets(ids: Array(ids))
                assets.removeAll { ids.contains($0.id) }
                selectedIDs = []
                onPermanentDelete(ids)
                // Permanent delete always removes the local copies too.
                if await PhotoLibraryService.ensureAccess() {
                    let localIDs = await PhotoLibraryService.localIdentifiers(matching: toDelete)
                    await PhotoLibraryService.deleteAssets(localIdentifiers: localIDs)
                }
            } catch {
                actionError = error.localizedDescription
                isShowingActionError = true
            }
        }
    }
}
