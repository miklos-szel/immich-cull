import SwiftUI

/// Shown while matching Immich assets against the local photo library.
///
/// That search walks the photo library and can take a moment on a large one.
/// Silently, it looks like the app has hung, and the system's delete
/// confirmation then appears long after the tap that caused it — with no
/// indication of what is asking or why.
struct PhotoLibrarySearchNoticeView: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Finding these photos on your iPhone…")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("photoLibrarySearchNotice")
    }
}
