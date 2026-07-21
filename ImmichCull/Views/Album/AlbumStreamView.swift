import SwiftUI

/// Full-screen stream of every asset in a selection — an album, the entire roll,
/// or the not-in-any-album pile — as one long lazy grid (no pagination). Press
/// and drag paints a multi-selection Photos-style, auto-scrolling at the edges;
/// the selection can be moved to the Immich trash. The media type shown is
/// switchable at the top. A body tap selects a photo; the corner cull icon (or
/// the toolbar "Cull") opens the per-image culler.
struct AlbumStreamView: View {
    let selection: AlbumSelection
    /// Hands the cull request up to Home, which dismisses this grid and presents
    /// the deck — rather than stacking the deck on top of the grid, which leaves
    /// the grid's toolbar (Select All, etc.) colliding with the deck's.
    var onStartCull: (String?) -> Void = { _ in }

    @Environment(SettingsStore.self) private var settings
    @Environment(StatsStore.self) private var stats
    @Environment(\.dismiss) private var dismiss

    private static let maxAssets = 5000

    /// Both media types are held so switching the filter is a local operation.
    @State private var allAssets: [ImmichAsset] = []
    /// Favourite / culled state per asset, for the badges.
    @State private var states: [String: AssetCullState] = [:]
    @State private var filter: MediaTypeFilter = .all
    @State private var didSetInitialFilter = false
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var selectedIDs: Set<String> = []
    @State private var isConfirmingTrash = false
    @State private var actionError: String?
    @State private var isShowingActionError = false

    private var assets: [ImmichAsset] {
        allAssets.filter { filter.includes($0.type) }
    }

    private var allSelected: Bool {
        !assets.isEmpty && selectedIDs.count == assets.count
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading…")
                } else if let loadError {
                    ContentUnavailableView {
                        Label("Couldn't load photos", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(loadError)
                    } actions: {
                        Button("Retry", action: retry)
                    }
                } else if assets.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing here", systemImage: "photo.on.rectangle")
                    } description: {
                        Text("No \(filter.label.lowercased()) here.")
                    }
                } else if let client = settings.client {
                    grid(client: client)
                }
            }
            .navigationTitle(selection.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // An X with a distinct label, not "Done": CullView (and its
                    // trash bin) present *over* this view, so a shared "Done"/
                    // "Close" label would make every query for theirs ambiguous.
                    Button(action: dismiss.callAsFunction) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close grid")
                    .accessibilityIdentifier("albumStreamDone")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // Select exactly one photo to start there; otherwise start
                    // from the first.
                    Button("Cull", systemImage: "rectangle.stack") {
                        startCulling(from: selectedIDs.count == 1 ? selectedIDs.first : nil)
                    }
                    .accessibilityIdentifier("albumStreamCull")
                    .disabled(assets.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    MediaFilterToolbarButton(filter: filter, select: { filter = $0 })
                }
                if !assets.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(allSelected ? "Deselect All" : "Select All", action: toggleSelectAll)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !selectedIDs.isEmpty {
                    trashButton
                }
            }
            .alert("Couldn't move to trash", isPresented: $isShowingActionError) {
            } message: {
                Text(actionError ?? "")
            }
            .task { await load() }
        }
    }

    private func grid(client: ImmichClient) -> some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                ForEach(assets) { asset in
                    CleanupGridCellView(
                        asset: asset,
                        isSelected: selectedIDs.contains(asset.id),
                        caption: nil,
                        state: states[asset.id] ?? AssetCullState(),
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
            autoScroll: true,
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
            ? String(localized: "Move 1 asset to the Immich trash?")
            : String(localized: "Move \(selectedIDs.count) assets to the Immich trash?")
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

    private func startCulling(from assetID: String?) {
        onStartCull(assetID)
        dismiss()
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
        if !didSetInitialFilter {
            filter = settings.mediaFilter
            didSetInitialFilter = true
        }
        guard isLoading else { return }
        guard let client = settings.client else {
            loadError = String(localized: "Not connected to a server.")
            isLoading = false
            return
        }
        do {
            allAssets = try await client.fetchAssets(
                albumIDs: selection.albumIDs, tagIDs: nil, order: "desc",
                limit: Self.maxAssets, isNotInAlbum: selection.isNotInAlbum ? true : nil
            )
        } catch {
            loadError = error.localizedDescription
            isLoading = false
            return
        }
        // Show the grid immediately; the culled/favourite badges fill in after,
        // so a slow tag lookup on a big library doesn't hold up the photos.
        isLoading = false
        await seedStates(client: client)
    }

    /// Marks which photos are already favourited or culled, so the grid shows
    /// the same badges the deck does. Favourite comes free with the asset; the
    /// culled set is a tag lookup that degrades to "none" on failure.
    private func seedStates(client: ImmichClient) async {
        let culled = (try? await client.assetIDs(
            withAnyTagNamed: settings.checkedTagNames + [settings.markTagName]
        )) ?? []
        states = allAssets.reduce(into: [:]) { result, asset in
            result[asset.id] = AssetCullState(
                isFavorite: asset.isFavorite ?? false,
                isInDestinationAlbum: false,
                isChecked: culled.contains(asset.id)
            )
        }
    }

    private func trashSelected() {
        guard let client = settings.client else { return }
        let ids = selectedIDs
        // Include any paired Live Photo movies so they're trashed with the still.
        let serverIDs = allAssets.filter { ids.contains($0.id) }.idsIncludingLivePhotoPairs
        Task {
            do {
                try await client.trashAssets(ids: serverIDs)
                stats.recordTrashed(count: ids.count)
                allAssets.removeAll { ids.contains($0.id) }
                selectedIDs = []
            } catch {
                actionError = error.localizedDescription
                isShowingActionError = true
            }
        }
    }
}
