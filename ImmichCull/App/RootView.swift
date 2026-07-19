import SwiftUI

struct RootView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        Group {
            if settings.isConfigured {
                HomeView()
            } else {
                SetupView()
            }
        }
        .preferredColorScheme(settings.appearance.colorScheme)
    }
}

#Preview {
    RootView()
        .environment(SettingsStore())
        .environment(StatsStore())
}
