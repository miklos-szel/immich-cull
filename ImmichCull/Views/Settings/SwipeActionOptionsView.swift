import SwiftUI

/// Shared option list for the swipe-direction pickers in Settings.
struct SwipeActionOptionsView: View {
    var body: some View {
        ForEach(SwipeAction.allCases) { action in
            Label(action.label, systemImage: action.systemImage)
                .tag(action)
        }
    }
}
