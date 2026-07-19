import SwiftUI

/// Banner above the card naming the action the current drag will trigger.
/// It always occupies its slot in the layout and fades via `progress`, so
/// appearing/disappearing never reflows (and never flickers) the image below.
struct SwipeActionLineView: View {
    let action: SwipeAction
    let progress: Double

    var body: some View {
        Label(action.label, systemImage: action.systemImage)
            .font(.headline)
            .bold()
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(action.tint, in: .rect(cornerRadius: 12))
            .opacity(progress)
            .animation(.easeOut(duration: 0.15), value: progress)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
