import SwiftUI

/// Browses the Immich trash and restores selected assets.
struct TrashBinView: View {
    let client: ImmichClient
    /// Reports assets that left the trash — restored or permanently deleted —
    /// so the caller can drop them from state that assumed they were binned.
    var onAssetsLeftTrash: (Set<String>) -> Void = { _ in }

    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var assets: [ImmichAsset] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var selectedIDs: Set<String> = []
    @State private var isShowingActionError = false
    @State private var actionError: String?
    @State private var isConfirmingDelete = false
    @State private var isConfirmingEmpty = false
    /// Matching Immich assets to local photos walks the photo library, which
    /// takes noticeable time on a big one. Without this the app looks frozen
    /// and the iOS delete confirmation seems to arrive out of nowhere.
    @State private var isSearchingPhotoLibrary = false

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
    }

    /// Sits under the selection actions rather than in the toolbar, so it can't
    /// be mistaken for "Select All"; the confirmation dialog guards the mis-tap.
    private var emptyTrashButton: some View {
        Button(role: .destructive, action: confirmEmpty) {
            Label("Empty Trash", systemImage: "trash.slash")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(.red)
        .accessibilityIdentifier("emptyTrashButton")
        .confirmationDialog(
            emptyDialogTitle,
            isPresented: $isConfirmingEmpty,
            titleVisibility: .visible
        ) {
            Button("Delete All Permanently", role: .destructive, action: emptyTrash)
        } message: {
            Text("This cannot be undone.")
        }
    }

    private var actionBar: some View {
        VStack(spacing: 8) {
            if isSearchingPhotoLibrary {
                PhotoLibrarySearchNoticeView()
            }
            selectionActions
            // Outside the group above: emptying the bin doesn't need a selection.
            emptyTrashButton
        }
        .padding()
        .background(.bar)
        // A permanent delete is mid-flight while the library search runs;
        // tapping Delete or Empty Trash again would start a second one.
        .disabled(isSearchingPhotoLibrary)
    }

    private var selectionActions: some View {
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
    }

    private var emptyDialogTitle: String {
        String(localized: "Permanently delete all \(assets.count) from Immich and this device?")
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
                onAssetsLeftTrash(ids)
            } catch {
                actionError = error.localizedDescription
                isShowingActionError = true
            }
        }
    }

    private func confirmDelete() {
        isConfirmingDelete = true
    }

    private func confirmEmpty() {
        isConfirmingEmpty = true
    }

    private func deleteSelectedPermanently() {
        permanentlyDelete(assets.filter { selectedIDs.contains($0.id) })
    }

    private func emptyTrash() {
        permanentlyDelete(assets)
    }

    /// Removes the local copies *before* deleting on the server, not after.
    ///
    /// Between the two there is a window where the photo is on the phone but
    /// no longer on the server — which is exactly the state that makes the
    /// official Immich app's auto-backup upload it again, undoing the delete.
    /// Doing the server side last keeps that window closed: once the server
    /// record goes, there is nothing left locally to re-upload.
    ///
    /// Failing the local step doesn't abort the server delete — the user asked
    /// for the photo gone — but it does warn, because that is the case where
    /// backup can put it back.
    private func permanentlyDelete(_ toDelete: [ImmichAsset]) {
        let ids = Set(toDelete.map(\.id))
        Task {
            do {
                var localCopiesRemain = false
                if await PhotoLibraryService.ensureAccess() {
                    isSearchingPhotoLibrary = true
                    let localIDs = await PhotoLibraryService.localIdentifiers(matching: toDelete)
                    isSearchingPhotoLibrary = false
                    if !localIDs.isEmpty {
                        localCopiesRemain = await PhotoLibraryService
                            .deleteAssets(localIdentifiers: localIDs) == false
                    }
                } else {
                    // Without library access we cannot even look, let alone
                    // delete — which is precisely the case where backup
                    // silently restores what was just deleted.
                    localCopiesRemain = true
                }

                try await client.permanentlyDeleteAssets(ids: Array(ids))
                assets.removeAll { ids.contains($0.id) }
                selectedIDs.subtract(ids)
                onAssetsLeftTrash(ids)

                if localCopiesRemain {
                    actionError = String(localized: "Deleted from Immich, but the copies are still on this iPhone. If Immich's auto-backup is on, it may upload them again.")
                    isShowingActionError = true
                }
            } catch {
                isSearchingPhotoLibrary = false
                actionError = error.localizedDescription
                isShowingActionError = true
            }
        }
    }
}
