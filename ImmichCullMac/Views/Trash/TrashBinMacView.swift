import SwiftUI

/// Browses the Immich trash: restore assets, or permanently delete them (which
/// also removes the matching local Photos item, per the app-wide rule).
struct TrashBinMacView: View {
    let client: ImmichClient
    /// Reports which assets left the bin and whether they were restored (vs.
    /// permanently deleted), so the caller can adjust its badge locally.
    let onAssetsLeftTrash: (_ ids: Set<String>, _ restored: Bool) -> Void

    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var assets: [ImmichAsset] = []
    @State private var selectedIDs: Set<String> = []
    @State private var phase: Phase = .loading
    @State private var confirmDelete = false
    @State private var actionError: String?
    @State private var isSearchingPhotoLibrary = false

    private enum Phase: Equatable { case loading, loaded, empty, failed(String) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .task { await load() }
        .alert("Something went wrong", isPresented: Binding(
            get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
        .confirmationDialog(deletePrompt, isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Permanently", role: .destructive) { Task { await permanentlyDelete() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone. Matching photos are also removed from this Mac's Photos library.")
        }
    }

    private var header: some View {
        HStack {
            Text("Trash").font(.headline)
            Spacer()
            if !assets.isEmpty {
                Button(selectedIDs.count == assets.count ? "Deselect All" : "Select All") {
                    selectedIDs = selectedIDs.count == assets.count ? [] : Set(assets.map(\.id))
                }
                Button {
                    Task { await restore() }
                } label: {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                }
                .disabled(selectedIDs.isEmpty)
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(selectedIDs.isEmpty)
            }
            Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
        }
        .overlay {
            if isSearchingPhotoLibrary {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Finding these photos in your Photos library…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        // A delete is mid-flight while the library search runs; a second
        // Delete would start another.
        .disabled(isSearchingPhotoLibrary)
        .padding(12)
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ProgressView("Loading trash…").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't load trash", systemImage: "wifi.exclamationmark")
            } description: { Text(message) } actions: {
                Button("Retry") { Task { await load() } }
            }
        case .empty:
            ContentUnavailableView("Trash is empty", systemImage: "trash",
                                   description: Text("Assets you trash while culling show up here."))
        case .loaded:
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: settings.thumbnailSize), spacing: 6)], spacing: 6) {
                    ForEach(assets) { asset in
                        GridCellView(
                            asset: asset,
                            client: client,
                            apiKey: settings.apiKey,
                            state: AssetCullState(),
                            isSelected: selectedIDs.contains(asset.id),
                            isCursor: false)
                        .onTapGesture { toggle(asset.id) }
                    }
                }
                .padding(8)
            }
        }
    }

    private var deletePrompt: String {
        selectedIDs.count == 1 ? "Permanently delete 1 asset?"
                               : "Permanently delete \(selectedIDs.count) assets?"
    }

    private func toggle(_ id: String) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
    }

    // MARK: Actions

    private func load() async {
        phase = .loading
        do {
            assets = try await client.trashedAssets()
            phase = assets.isEmpty ? .empty : .loaded
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func restore() async {
        let targets = assets.filter { selectedIDs.contains($0.id) }
        guard !targets.isEmpty else { return }
        do {
            try await client.restoreAssets(ids: targets.idsIncludingLivePhotoPairs)
            finish(removing: Set(targets.map(\.id)), restored: true)
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func permanentlyDelete() async {
        let targets = assets.filter { selectedIDs.contains($0.id) }
        guard !targets.isEmpty else { return }
        do {
            // Local copies go first, the same as on iOS — see TrashPurger.
            let localCopiesRemain = try await TrashPurger.permanentlyDelete(targets, client: client) { searching in
                isSearchingPhotoLibrary = searching
            }
            finish(removing: Set(targets.map(\.id)), restored: false)
            if localCopiesRemain {
                actionError = String(localized: "Deleted from Immich, but the copies are still in this Mac's Photos library. If they are backed up to Immich again, they will come back.")
            }
        } catch {
            isSearchingPhotoLibrary = false
            actionError = error.localizedDescription
        }
    }

    private func finish(removing ids: Set<String>, restored: Bool) {
        assets.removeAll { ids.contains($0.id) }
        selectedIDs.subtract(ids)
        onAssetsLeftTrash(ids, restored)
        if assets.isEmpty { phase = .empty }
    }
}
