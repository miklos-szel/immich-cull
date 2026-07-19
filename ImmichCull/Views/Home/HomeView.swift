import SwiftUI

struct HomeView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.scenePhase) private var scenePhase
    @State private var albums: [ImmichAlbum] = []
    @State private var loadError: String?
    @State private var isLoading = true
    /// Keyed by album ID, not by value: an album's assetCount changes as you
    /// cull, and a value-keyed set would strand the old copy and double-count.
    @State private var selectedAlbumIDs: Set<String> = []
    @State private var entireRollSelected = true
    @State private var activeSelection: AlbumSelection?
    @State private var isShowingSettings = false
    @State private var isShowingTrashBin = false
    @State private var trashCount = 0
    /// Cleanup screens are pushed onto this path; emptying it means we're back
    /// on Home, which is one of the points where album counts may be stale.
    @State private var cleanupPath: [CleanupRoute] = []

    var body: some View {
        NavigationStack(path: $cleanupPath) {
            Group {
                if let loadError {
                    ContentUnavailableView {
                        Label("Couldn't load albums", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(loadError)
                    } actions: {
                        Button("Retry", action: reload)
                    }
                } else if isLoading {
                    ProgressView("Loading albums…")
                } else {
                    albumList
                }
            }
            .navigationTitle("immich-cull")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    TrashBinToolbarButton(
                        count: trashCount,
                        identifier: "homeTrashBinButton",
                        action: showTrashBin
                    )
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape", action: showSettings)
                }
            }
            .safeAreaInset(edge: .bottom) {
                startButton
            }
            // Anything that can trash assets or change album membership
            // refreshes the list on the way back, so counts stay truthful.
            .sheet(isPresented: $isShowingSettings, onDismiss: refreshHome) {
                SettingsView()
            }
            .sheet(isPresented: $isShowingTrashBin, onDismiss: refreshAlbums) {
                if let client = settings.client {
                    // The badge drops locally rather than by refetching: Immich's
                    // statistics endpoint lags writes, so an immediate re-read
                    // would report the pre-restore total.
                    TrashBinView(client: client) { ids in
                        trashCount = max(0, trashCount - ids.count)
                    }
                }
            }
            .fullScreenCover(item: $activeSelection, onDismiss: refreshHome) { selection in
                CullView(selection: selection)
            }
            .navigationDestination(for: CleanupRoute.self) { route in
                CleanupDestinationView(route: route)
            }
            .onChange(of: cleanupPath) { _, path in
                if path.isEmpty { refreshHome() }
            }
            // Catches edits made elsewhere (e.g. the Immich web UI).
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { refreshHome() }
            }
            .task {
                await loadAlbums()
                await refreshTrashCount()
            }
        }
    }

    private var albumList: some View {
        List {
            // Cleanup finders are temporarily hidden pending refinement; every
            // code path (CleanupRoute, the views, ImmichClient calls) is retained.
            // TODO: re-enable duplicates / blurry / screenshots / receipts finders.
            // Section {
            //     NavigationLink(value: CleanupRoute.duplicates) {
            //         Label("Find Duplicates", systemImage: "square.on.square")
            //     }
            //     NavigationLink(value: CleanupRoute.blurry) {
            //         Label("Find Blurry Photos", systemImage: "camera.filters")
            //     }
            //     NavigationLink(value: CleanupRoute.screenshots) {
            //         Label("Find Screenshots", systemImage: "camera.viewfinder")
            //     }
            //     NavigationLink(value: CleanupRoute.receipts) {
            //         Label("Find Receipts & Bills", systemImage: "doc.text.viewfinder")
            //     }
            // } header: {
            //     Text("Cleanup")
            // }

            Section {
                EntireRollRowView(isSelected: entireRollSelected, toggle: selectEntireRoll)
                ForEach(albums) { album in
                    AlbumRowView(
                        album: album,
                        isSelected: selectedAlbumIDs.contains(album.id),
                        thumbnailURL: thumbnailURL(for: album),
                        apiKey: settings.apiKey,
                        toggle: { toggle(album) }
                    )
                }
            } footer: {
                if albums.isEmpty {
                    Text("No albums on this server. You can still cull the entire roll.")
                }
            }
        }
        .refreshable { await loadAlbums() }
    }

    private var startButton: some View {
        Button(action: start) {
            Label(startTitle, systemImage: "rectangle.stack")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding()
        .background(.bar)
        .disabled(isLoading && loadError == nil)
    }

    private var startTitle: String {
        // Inflection markup doesn't render via String(localized:), so spell out the plural.
        if entireRollSelected || selectedAlbumIDs.isEmpty {
            return String(localized: "Cull Entire Roll")
        }
        switch selectedAlbumIDs.count {
        case 1: return String(localized: "Cull 1 Album")
        default: return String(localized: "Cull \(selectedAlbumIDs.count) Albums")
        }
    }

    private func thumbnailURL(for album: ImmichAlbum) -> URL? {
        guard let client = settings.client, let assetID = album.albumThumbnailAssetId else { return nil }
        return client.thumbnailURL(assetID: assetID, size: "thumbnail")
    }

    private func selectEntireRoll() {
        entireRollSelected = true
        selectedAlbumIDs.removeAll()
    }

    private func toggle(_ album: ImmichAlbum) {
        if selectedAlbumIDs.contains(album.id) {
            selectedAlbumIDs.remove(album.id)
        } else {
            selectedAlbumIDs.insert(album.id)
        }
        // Picking specific albums is mutually exclusive with the entire roll.
        entireRollSelected = selectedAlbumIDs.isEmpty
    }

    private func start() {
        if entireRollSelected || selectedAlbumIDs.isEmpty {
            activeSelection = .entireLibrary
        } else {
            let ordered = albums.filter { selectedAlbumIDs.contains($0.id) }
            activeSelection = .albums(ordered)
        }
    }

    private func showSettings() {
        isShowingSettings = true
    }

    private func showTrashBin() {
        isShowingTrashBin = true
    }

    private func reload() {
        isLoading = true
        loadError = nil
        Task { await loadAlbums() }
    }

    /// Silent reload — no spinner, since the list is already on screen.
    private func refreshAlbums() {
        Task { await loadAlbums() }
    }

    private func refreshHome() {
        Task {
            await loadAlbums()
            await refreshTrashCount()
        }
    }

    /// Deliberately not called when the trash sheet closes: that sheet already
    /// reported what left the bin, and re-reading the lagging statistics
    /// endpoint would put the stale total back.
    private func refreshTrashCount() async {
        guard let client = settings.client else { return }
        if let stats = try? await client.trashStatistics() {
            trashCount = stats.total
        }
    }

    private func loadAlbums() async {
        guard let client = settings.client else {
            isLoading = false
            return
        }
        do {
            albums = try await client.albums()
            // Forget albums that no longer exist server-side.
            selectedAlbumIDs.formIntersection(Set(albums.map(\.id)))
            if selectedAlbumIDs.isEmpty {
                entireRollSelected = true
            }
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}

#Preview {
    HomeView()
        .environment(SettingsStore())
        .environment(StatsStore())
}
