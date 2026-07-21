import SwiftUI

struct HomeView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.scenePhase) private var scenePhase
    @State private var albums: [ImmichAlbum] = []
    @State private var loadError: String?
    @State private var isLoading = true
    /// The selection whose full-screen stream is open, if any. Every row —
    /// entire roll, not-in-album, or an album — opens one; culling is launched
    /// from inside it.
    @State private var streamSelection: AlbumSelection?
    /// Set while a stream is dismissing to hand off into the deck; the stream's
    /// `onDismiss` then promotes it to `cullRequest`. Presenting the deck only
    /// after the grid has fully dismissed avoids stacking two covers at once.
    @State private var pendingCull: CullRequest?
    @State private var cullRequest: CullRequest?
    @State private var isShowingSettings = false
    @State private var isShowingAbout = false
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
            // No title: the app's own name tells you nothing you don't already
            // know, and an inline empty title lets the bar collapse to the
            // toolbar buttons instead of reserving a large-title header.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: showAbout) {
                        Image("Logo")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 28)
                            .clipShape(.rect(cornerRadius: 6))
                    }
                    .accessibilityLabel("About immich-cull")
                }
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
            // Anything that can trash assets or change album membership
            // refreshes the list on the way back, so counts stay truthful.
            .sheet(isPresented: $isShowingSettings, onDismiss: refreshHome) {
                SettingsView()
            }
            .sheet(isPresented: $isShowingAbout) {
                AboutView()
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
            .fullScreenCover(item: $streamSelection, onDismiss: onStreamDismissed) { selection in
                AlbumStreamView(selection: selection, onStartCull: { startID in
                    pendingCull = CullRequest(selection: selection, startAssetID: startID)
                })
            }
            .fullScreenCover(item: $cullRequest, onDismiss: refreshHome) { request in
                CullView(selection: request.selection, startAssetID: request.startAssetID)
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
                EntireRollRowView(open: { streamSelection = .entireLibrary })
                NotInAnyAlbumRowView(open: { streamSelection = .notInAnyAlbum })
                ForEach(displayAlbums) { album in
                    AlbumRowView(
                        album: album,
                        thumbnailURL: thumbnailURL(for: album),
                        apiKey: settings.apiKey,
                        open: { streamSelection = .albums([album]) }
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

    private var displayAlbums: [ImmichAlbum] {
        albums.sorted(by: settings.order)
    }

    private func thumbnailURL(for album: ImmichAlbum) -> URL? {
        guard let client = settings.client, let assetID = album.albumThumbnailAssetId else { return nil }
        return client.thumbnailURL(assetID: assetID, size: "thumbnail")
    }

    /// After the grid closes, refresh Home and, if the close was a hand-off into
    /// culling, present the deck now that no other cover is on screen.
    private func onStreamDismissed() {
        refreshHome()
        if let pendingCull {
            cullRequest = pendingCull
            self.pendingCull = nil
        }
    }

    private func showSettings() {
        isShowingSettings = true
    }

    private func showAbout() {
        isShowingAbout = true
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
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}

/// A request to open the culling deck for a selection, optionally positioned on
/// a specific photo (tapped in the grid).
private struct CullRequest: Identifiable {
    let selection: AlbumSelection
    let startAssetID: String?
    var id: String { selection.id + "|" + (startAssetID ?? "") }
}

#Preview {
    HomeView()
        .environment(SettingsStore())
        .environment(StatsStore())
}
