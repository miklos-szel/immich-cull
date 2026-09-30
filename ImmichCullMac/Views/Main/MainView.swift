import SwiftUI

/// A sidebar source (library / unsorted / a specific album).
///
/// Albums are identified by ID, not by the `ImmichAlbum` value: that value
/// changes whenever its asset count does (e.g. after trashing from it), and a
/// value-keyed selection then matched no row and the sidebar lost its highlight.
enum SidebarItem: Hashable {
    case entireLibrary
    case notInAnyAlbum
    case album(id: String)
}

/// A request to open the culling deck for a selection, optionally at a photo.
struct CullRequest: Identifiable {
    let selection: AlbumSelection
    let startAssetID: String?
    /// The grid's filter when the deck was launched from it.
    let mediaFilter: MediaTypeFilter?
    var id: String { selection.id + "|" + (startAssetID ?? "") }
}

struct MainView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.scenePhase) private var scenePhase

    @State private var albums: [ImmichAlbum] = []
    @State private var loadError: String?
    @State private var isLoading = true
    @State private var selection: SidebarItem? = .entireLibrary
    @State private var trashCount = 0
    @State private var cullRequest: CullRequest?
    @State private var showTrash = false
    /// After culling, the asset the grid should scroll back to.
    @State private var revealAssetID: String?
    @State private var albumSearch = ""

    var body: some View {
        Group {
            if let request = cullRequest {
                // The deck fills the whole (resizable) main window rather than a
                // fixed-size sheet, so the culling window can be resized freely.
                CullMacView(selection: request.selection, startAssetID: request.startAssetID,
                            mediaFilter: request.mediaFilter) { revealID, trashed in
                    revealAssetID = revealID
                    cullRequest = nil
                    // Local, not a statistics re-read: that endpoint lags the
                    // writes that just happened and would show the old total.
                    trashCount += trashed
                    refreshAlbums()
                }
            } else {
                NavigationSplitView {
                    sidebar
                        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
                } detail: {
                    detail
                }
            }
        }
        .sheet(isPresented: $showTrash, onDismiss: refreshAlbums) {
            if let client = settings.client {
                TrashBinMacView(client: client) { ids, _ in
                    trashCount = max(0, trashCount - ids.count)
                }
                .frame(minWidth: 760, idealWidth: 1000, maxWidth: .infinity,
                       minHeight: 560, idealHeight: 760, maxHeight: .infinity)
            }
        }
        .task {
            await loadAlbums()
            await refreshTrashCount()
        }
        // Catches edits made elsewhere (e.g. the Immich web UI) — the one time
        // re-reading the statistics is right, as no local write just happened.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await loadAlbums()
                await refreshTrashCount()
            }
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                Label("Entire Library", systemImage: "photo.on.rectangle.angled")
                    .tag(SidebarItem.entireLibrary)
                Label("Not in Any Album", systemImage: "questionmark.folder")
                    .tag(SidebarItem.notInAnyAlbum)
            }
            Section("Albums") {
                ForEach(sidebarAlbums) { album in
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(album.albumName).lineLimit(1)
                            Text("\(album.assetCount) items")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "rectangle.stack")
                    }
                    .tag(SidebarItem.album(id: album.id))
                }
                if albums.isEmpty && !isLoading {
                    Text("No albums on this server.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if sidebarAlbums.isEmpty {
                    Text("No albums match “\(albumSearch)”.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .searchable(text: $albumSearch, placement: .sidebar, prompt: "Search albums")
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    showTrash = true
                } label: {
                    Label("Trash", systemImage: "trash")
                    if trashCount > 0 {
                        Text("\(trashCount)")
                            .font(.caption.monospacedDigit())
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(.red, in: .capsule)
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(settings.shortcut(for: .showTrash))
                Spacer()
                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
            }
            .padding(8)
            .background(.bar)
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let loadError {
            ContentUnavailableView {
                Label("Couldn't load albums", systemImage: "wifi.exclamationmark")
            } description: {
                Text(loadError)
            } actions: {
                Button("Retry") { Task { await loadAlbums() } }
            }
        } else if let selection, let source = albumSelection(for: selection) {
            LibraryGridView(selection: source, albums: displayAlbums,
                            revealID: revealAssetID) { assetID, filter in
                cullRequest = CullRequest(selection: source, startAssetID: assetID, mediaFilter: filter)
            } onChanged: { trashed in
                trashCount += trashed
                refreshAlbums()
            }
            .id(selection)
        } else {
            ContentUnavailableView("Pick a source", systemImage: "sidebar.left",
                                   description: Text("Choose the library, the unsorted pile, or an album to begin."))
        }
    }

    private func albumSelection(for item: SidebarItem) -> AlbumSelection? {
        switch item {
        case .entireLibrary: .entireLibrary
        case .notInAnyAlbum: .notInAnyAlbum
        case .album(let id): albums.first { $0.id == id }.map { .albums([$0]) }
        }
    }

    private var displayAlbums: [ImmichAlbum] {
        albums.sorted { lhs, rhs in
            let l = lhs.sortDate ?? .distantPast
            let r = rhs.sortDate ?? .distantPast
            return settings.order == .newestFirst ? l > r : l < r
        }
    }

    /// Albums shown in the sidebar, narrowed by the search field.
    private var sidebarAlbums: [ImmichAlbum] {
        let query = albumSearch.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return displayAlbums }
        return displayAlbums.filter {
            $0.albumName.localizedCaseInsensitiveContains(query)
        }
    }

    // MARK: Data

    /// Album counts only. The trash badge is adjusted locally by whoever
    /// changed the bin: the statistics endpoint lags writes, so re-reading it
    /// right after one puts the stale total back.
    private func refreshAlbums() {
        Task { await loadAlbums() }
    }

    private func loadAlbums() async {
        guard let client = settings.client else { isLoading = false; return }
        do {
            albums = try await client.albums()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func refreshTrashCount() async {
        guard let client = settings.client else { return }
        if let stats = try? await client.trashStatistics() {
            trashCount = stats.total
        }
    }
}
