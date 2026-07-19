import SwiftUI

@main
struct ImmichCullApp: App {
    @State private var settings = SettingsStore()
    @State private var stats = StatsStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(stats)
        }
    }
}
