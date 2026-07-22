import SwiftUI

/// Shown when the queue empties. Its `.task` runs the local Photos cleanup —
/// guarded one-shot inside `CullSession`, so re-entering `.finished` (via a
/// media-filter narrow/widen) won't re-fire the system delete confirmation.
struct CullSummaryMacView: View {
    let session: CullSession
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.green)
            Text("All done")
                .font(.title.bold())
            Text("You reviewed \(session.reviewedCount) \(session.reviewedCount == 1 ? "item" : "items").")
                .foregroundStyle(.secondary)

            HStack(spacing: 28) {
                stat("Trashed", session.trashedCount, "trash", .red)
                stat("Skipped", session.skippedCount, "chevron.forward", .gray)
                stat("To Album", session.savedToAlbumCount, "rectangle.stack.badge.plus", .blue)
                stat("Favorited", session.favoritedCount, "heart.fill", .pink)
            }
            .padding(.vertical, 8)

            Button("Done", action: onDone)
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            // Removes the trashed items from the Mac's Photos library (must-have).
            await session.deleteTrashedFromPhotosIfEnabled()
        }
    }

    private func stat(_ title: String, _ value: Int, _ symbol: String, _ tint: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text("\(value)").font(.title2.monospacedDigit().bold())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}
