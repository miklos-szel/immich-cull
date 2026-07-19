import SwiftUI

/// The only swipe marker: a red trash badge that fades in while the current
/// drag would bin the photo. Overlaid on the deck, so it never affects layout.
struct TrashMarkerView: View {
    let progress: Double

    var body: some View {
        Label("Trash", systemImage: "trash.fill")
            .font(.headline)
            .bold()
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.red.opacity(0.92), in: .capsule)
            .opacity(progress)
            .animation(.easeOut(duration: 0.15), value: progress)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
