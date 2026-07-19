import SwiftUI

/// Compact live counters for the current culling session.
struct SessionStatsView: View {
    let session: CullSession

    var body: some View {
        HStack(spacing: 16) {
            counter(session.trashedCount, systemImage: "trash.fill", tint: .red)
            counter(session.skippedCount, systemImage: "chevron.forward.circle.fill", tint: .gray)
            counter(session.savedToAlbumCount, systemImage: "rectangle.stack.badge.plus", tint: .blue)
            if session.favoritedCount > 0 {
                counter(session.favoritedCount, systemImage: "heart.fill", tint: .pink)
            }
        }
        .font(.footnote)
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(session.trashedCount) trashed, \(session.skippedCount) reviewed, \(session.savedToAlbumCount) added to album, \(session.favoritedCount) favorited")
    }

    private func counter(_ count: Int, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .imageScale(.small)
            Text(count, format: .number)
                .foregroundStyle(.secondary)
        }
    }
}
