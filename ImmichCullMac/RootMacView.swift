import SwiftUI

struct RootMacView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        Group {
            if settings.isConfigured {
                MainView()
            } else {
                ConnectionView()
            }
        }
        .preferredColorScheme(settings.appearance.colorScheme)
    }
}
