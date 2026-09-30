import SwiftUI

/// Full-screen culling flow for one album selection.
struct CullView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(StatsStore.self) private var stats
    @Environment(\.dismiss) private var dismiss

    let selection: AlbumSelection
    /// When set, the deck opens already positioned on this photo — used when a
    /// grid cell's cull icon launches the run from a specific image.
    var startAssetID: String?
    /// The launching grid's filter, so the photo it started from is in the run.
    var mediaFilter: MediaTypeFilter?
    /// Called on close with how much the Immich bin grew during this screen,
    /// so Home can move its badge without re-reading the lagging statistics.
    var onClose: (_ trashDelta: Int) -> Void = { _ in }

    @State private var session: CullSession?
    @State private var isShowingTrashBin = false
    @State private var isShowingGrid = false
    /// Items that were already in the Immich bin before this session; the
    /// badge adds this session's own trashed count on top, so it updates
    /// instantly instead of waiting on a server statistics round-trip.
    @State private var trashBaseline = 0
    /// Items that were in the bin before this session and left it through the
    /// bin sheet here — the part of the change `session.trashedCount` can't see.
    @State private var preexistingRemoved = 0
    @State private var isClosing = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(selection.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close", systemImage: "xmark", action: close)
                            .disabled(isClosing)
                    }
                    ToolbarItem(placement: .principal) {
                        Button(action: showGrid) {
                            HStack(spacing: 4) {
                                Text(selection.title)
                                    .font(.headline)
                                    .lineLimit(1)
                                Image(systemName: "chevron.down")
                                    .font(.caption2.bold())
                            }
                        }
                        .foregroundStyle(.primary)
                        .accessibilityLabel("\(selection.title), browse all photos")
                        .accessibilityIdentifier("albumTitleButton")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        if let session {
                            MediaFilterToolbarButton(
                                filter: session.mediaFilter,
                                select: session.setMediaFilter
                            )
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        TrashBinToolbarButton(count: trashCount, action: showTrashBin)
                    }
                }
                .overlay(alignment: .top) {
                    if let session, let message = session.errorMessage {
                        ErrorBannerView(message: message) {
                            session.errorMessage = nil
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if session?.isSearchingPhotoLibrary == true {
                        PhotoLibrarySearchNoticeView()
                            .padding()
                            .background(.bar)
                    }
                }
        }
        .sheet(isPresented: $isShowingTrashBin) {
            if let client = settings.client {
                TrashBinView(client: client) { ids, restored in
                    // Items this session trashed drop out of session.trashedCount;
                    // the rest came from the pre-existing bin contents.
                    let ownedBySession = session?.forgetTrashedAssets(ids: ids, restored: restored) ?? 0
                    let preexisting = ids.count - ownedBySession
                    trashBaseline = max(0, trashBaseline - preexisting)
                    preexistingRemoved += preexisting
                }
            }
        }
        .sheet(isPresented: $isShowingGrid) {
            if let session, let client = settings.client {
                CullGridView(session: session, client: client, title: selection.title)
            }
        }
        .task { await startSession() }
        // Read the pre-existing bin size once. Immich's statistics endpoint
        // lags behind writes, so re-reading it mid-session would overwrite the
        // (correct) local count with a stale one — the badge is maintained
        // locally from here on.
        .task { await loadTrashBaseline() }
    }

    private var trashCount: Int {
        max(0, trashBaseline + (session?.trashedCount ?? 0))
    }

    @ViewBuilder private var content: some View {
        if let session, let client = settings.client {
            switch session.phase {
            case .loading:
                ProgressView("Loading photos…")
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't load photos", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Retry", action: retry)
                }
            case .finished:
                // No photo cleanup here: it runs on close (`CullSession.close`),
                // so an early exit gets it too and "Undo Last" can't outrun it.
                CullSummaryView(session: session, done: close)
            case .active:
                CullDeckView(session: session, client: client)
            }
        } else {
            ProgressView()
        }
    }

    private func startSession() async {
        guard session == nil, let client = settings.client else { return }
        let newSession = CullSession(settings: settings, client: client, selection: selection,
                                     stats: stats, mediaFilter: mediaFilter)
        session = newSession
        await newSession.start(focusAssetID: startAssetID)
    }

    private func retry() {
        Task { await session?.start() }
    }

    private func showTrashBin() {
        isShowingTrashBin = true
    }

    private func showGrid() {
        isShowingGrid = true
    }

    private func loadTrashBaseline() async {
        guard let client = settings.client else { return }
        if let stats = try? await client.trashStatistics() {
            // The server total already includes this session's trashing.
            trashBaseline = max(0, stats.total - (session?.trashedCount ?? 0))
        }
    }

    /// Closing ends the session: queued server work finishes and this run's
    /// trashes leave the iPhone library (iOS confirms) before the screen goes.
    private func close() {
        guard !isClosing else { return }
        isClosing = true
        Task {
            await session?.close()
            onClose((session?.trashedCount ?? 0) - preexistingRemoved)
            dismiss()
        }
    }
}
