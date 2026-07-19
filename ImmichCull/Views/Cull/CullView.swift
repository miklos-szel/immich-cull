import SwiftUI

/// Full-screen culling flow for one album selection.
struct CullView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(StatsStore.self) private var stats
    @Environment(\.dismiss) private var dismiss

    let selection: AlbumSelection

    @State private var session: CullSession?
    @State private var isShowingTrashBin = false
    @State private var trashCount = 0

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(selection.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close", systemImage: "xmark", action: close)
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
        }
        .sheet(isPresented: $isShowingTrashBin, onDismiss: refreshTrashCount) {
            if let client = settings.client {
                TrashBinView(client: client) { deletedIDs in
                    session?.forgetTrashedAssets(ids: deletedIDs)
                }
            }
        }
        .task { await startSession() }
        // Refresh the badge initially and whenever something is trashed/restored.
        .task(id: sessionTrashedCount) { await loadTrashCount() }
    }

    private var sessionTrashedCount: Int { session?.trashedCount ?? 0 }

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
                CullSummaryView(session: session, done: close)
                    .task { await session.deleteTrashedFromPhotosIfEnabled() }
            case .active:
                CullDeckView(session: session, client: client)
            }
        } else {
            ProgressView()
        }
    }

    private func startSession() async {
        guard session == nil, let client = settings.client else { return }
        let newSession = CullSession(settings: settings, client: client, selection: selection, stats: stats)
        session = newSession
        await newSession.start()
    }

    private func retry() {
        Task { await session?.start() }
    }

    private func showTrashBin() {
        isShowingTrashBin = true
    }

    private func refreshTrashCount() {
        Task { await loadTrashCount() }
    }

    private func loadTrashCount() async {
        guard let client = settings.client else { return }
        if let stats = try? await client.trashStatistics() {
            trashCount = stats.total
        }
    }

    private func close() {
        dismiss()
    }
}
