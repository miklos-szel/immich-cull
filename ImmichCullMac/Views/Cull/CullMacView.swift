import SwiftUI

/// Owns one `CullSession` and presents the deck / summary. Rendered inline in
/// the resizable main window (not a sheet), so the window drives the deck's
/// size — see `MainView` and the macOS culling convention.
struct CullMacView: View {
    let selection: AlbumSelection
    let startAssetID: String?
    /// The grid's media filter at launch, so the photo you started from is in the run.
    var mediaFilter: MediaTypeFilter?
    /// Returns to the library, passing the asset that was on screen so the grid
    /// can scroll back to it. Called inline (the deck fills the main window
    /// rather than a fixed-size sheet, so the window stays resizable).
    /// Also reports how many assets the run left in the trash, so the caller
    /// can move its badge without re-reading the lagging statistics endpoint.
    let onClose: (_ revealAssetID: String?, _ trashedCount: Int) -> Void

    @Environment(SettingsStore.self) private var settings
    @Environment(StatsStore.self) private var stats

    @State private var session: CullSession?
    @State private var isClosing = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Group {
                if let session {
                    switch session.phase {
                    case .loading:
                        ProgressView("Loading photos…").frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .active:
                        CullDeckMacView(session: session)
                    case .finished:
                        CullSummaryMacView(session: session) { close(revealing: nil) }
                    case .failed(let message):
                        ContentUnavailableView {
                            Label("Couldn't start culling", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text(message)
                        } actions: {
                            Button("Close") { close(revealing: nil) }
                        }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .task { await startSession() }
    }

    private var header: some View {
        HStack {
            Button {
                // Hand back the asset on screen so the grid returns to it.
                close(revealing: session?.current?.id)
            } label: {
                Label("Done", systemImage: "chevron.left")
            }
            .keyboardShortcut(.cancelAction)
            .disabled(isClosing)
            Spacer()
            if session?.isSearchingPhotoLibrary == true {
                ProgressView().controlSize(.small)
                Text("Finding these photos in your Photos library…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text(selection.title).font(.headline)
            }
            Spacer()
            // Balances the leading button so the title stays centered.
            Label("Done", systemImage: "chevron.left").hidden()
        }
        .padding(12)
    }

    private func startSession() async {
        guard session == nil, let client = settings.client else { return }
        let newSession = CullSession(settings: settings, client: client, selection: selection,
                                     stats: stats, mediaFilter: mediaFilter)
        session = newSession
        await newSession.start(focusAssetID: startAssetID)
    }

    /// Leaving ends the session: its queued server work finishes and its
    /// trashes are removed from the Photos library — whether or not the run
    /// reached the end — before the grid comes back.
    private func close(revealing assetID: String?) {
        guard !isClosing else { return }
        isClosing = true
        Task {
            await session?.close()
            onClose(assetID, session?.trashedCount ?? 0)
        }
    }
}
