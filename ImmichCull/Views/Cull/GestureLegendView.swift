import SwiftUI

/// Compact reminder of the configured swipe mapping.
struct GestureLegendView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        HStack(spacing: 10) {
            ForEach(SwipeDirection.allCases) { direction in
                let action = settings.action(for: direction)
                if action != .disabled {
                    HStack(spacing: 1) {
                        Image(systemName: direction.arrowSystemImage)
                        Image(systemName: action.systemImage)
                    }
                    .foregroundStyle(action.tint)
                }
            }
        }
        .imageScale(.small)
        .accessibilityLabel(legendDescription)
    }

    private var legendDescription: String {
        SwipeDirection.allCases.compactMap { direction in
            let action = settings.action(for: direction)
            guard action != .disabled else { return nil }
            return String(localized: "Swipe \(direction.label) to \(action.label)")
        }
        .joined(separator: ", ")
    }
}
