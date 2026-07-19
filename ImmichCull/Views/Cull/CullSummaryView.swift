import SwiftUI

/// Shown when every asset in the session has been reviewed.
struct CullSummaryView: View {
    let session: CullSession
    let done: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            ContentUnavailableView {
                Label("All done", systemImage: "checkmark.seal.fill")
            } description: {
                summaryText
            } actions: {
                if session.canUndo {
                    Button("Undo Last", systemImage: "arrow.uturn.backward", action: session.undo)
                }
                Button("Done", action: done)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var summaryText: Text {
        if session.reviewedCount == 0 {
            Text("Nothing left to review here. Everything has already been checked.")
        } else {
            Text("Reviewed ^[\(session.reviewedCount) photo](inflect: true): \(session.trashedCount) trashed, \(session.savedToAlbumCount) added to the album, \(session.favoritedCount) favorited.")
        }
    }
}
