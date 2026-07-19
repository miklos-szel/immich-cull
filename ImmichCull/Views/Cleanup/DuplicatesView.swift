import SwiftUI

/// Shows Immich's duplicate groups; selected assets get moved to the trash.
struct DuplicatesView: View {
    let client: ImmichClient

    @Environment(StatsStore.self) private var stats

    @State private var groups: [DuplicateGroup] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var selectedIDs: Set<String> = []
    @State private var isConfirmingTrash = false
    @State private var isShowingActionError = false
    @State private var actionError: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading duplicates…")
            } else if let loadError {
                ContentUnavailableView {
                    Label("Couldn't load duplicates", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Retry", action: retry)
                }
            } else if groups.isEmpty {
                ContentUnavailableView {
                    Label("No duplicates", systemImage: "checkmark.seal")
                } description: {
                    Text("Immich hasn't detected any duplicate assets. Duplicate detection requires machine learning on the server.")
                }
            } else {
                groupList
            }
        }
        .navigationTitle("Duplicates")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if !groups.isEmpty {
                trashButton
            }
        }
        .alert("Couldn't move to trash", isPresented: $isShowingActionError) {
        } message: {
            Text(actionError ?? "")
        }
        .task { await load() }
    }

    private var groupList: some View {
        List {
            Section {
                ForEach(groups) { group in
                    DuplicateGroupRowView(group: group, selectedIDs: $selectedIDs, client: client)
                }
            } footer: {
                Text("Immich's suggested copies to remove are preselected. Tap a photo to toggle.")
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

    private func confirmTrash() {
        isConfirmingTrash = true
    }

    private func retry() {
        isLoading = true
        loadError = nil
        Task { await load() }
    }

    private func load() async {
        do {
            let loaded = try await client.duplicates().filter { $0.assets.count > 1 }
            groups = loaded
            selectedIDs = Set(loaded.flatMap(\.defaultTrashIDs))
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
                groups = groups.compactMap { group in
                    let remaining = group.assets.filter { !ids.contains($0.id) }
                    guard remaining.count > 1 else { return nil }
                    return DuplicateGroup(
                        duplicateId: group.duplicateId,
                        assets: remaining,
                        suggestedKeepAssetIds: group.suggestedKeepAssetIds
                    )
                }
                selectedIDs = []
            } catch {
                actionError = error.localizedDescription
                isShowingActionError = true
            }
        }
    }
}
