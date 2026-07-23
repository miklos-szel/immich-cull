import SwiftUI

/// Owns one `CullSession` and presents the deck / summary. Rendered inline in
/// the resizable main window (not a sheet), so the window drives the deck's
/// size — see `MainView` and the macOS culling convention.
struct CullMacView: View {
    let selection: AlbumSelection
    let startAssetID: String?
    /// Returns to the library, passing the asset that was on screen so the grid
    /// can scroll back to it. Called inline (the deck fills the main window
    /// rather than a fixed-size sheet, so the window stays resizable).
    let onClose: (_ revealAssetID: String?) -> Void

    @Environment(SettingsStore.self) private var settings
    @Environment(StatsStore.self) private var stats

    @State private var session: CullSession?

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
                        CullSummaryMacView(session: session) { onClose(nil) }
                    case .failed(let message):
                        ContentUnavailableView {
                            Label("Couldn't start culling", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text(message)
                        } actions: {
                            Button("Close") { onClose(nil) }
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
                onClose(session?.current?.id)
            } label: {
                Label("Done", systemImage: "chevron.left")
            }
            .keyboardShortcut(.cancelAction)
            Spacer()
            Text(selection.title).font(.headline)
            Spacer()
            // Balances the leading button so the title stays centered.
            Label("Done", systemImage: "chevron.left").hidden()
        }
        .padding(12)
    }

    private func startSession() async {
        guard session == nil, let client = settings.client else { return }
        let newSession = CullSession(settings: settings, client: client, selection: selection, stats: stats)
        session = newSession
        await newSession.start()
        if let startAssetID {
            newSession.jump(toID: startAssetID)
        }
    }
}
