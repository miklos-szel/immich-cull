import SwiftUI

@main
struct ImmichCullMacApp: App {
    @State private var settings = SettingsStore()
    @State private var stats = StatsStore()

    var body: some Scene {
        WindowGroup {
            RootMacView()
                .environment(settings)
                .environment(stats)
                .frame(minWidth: 900, minHeight: 600)
        }
        .commands {
            CullCommands()
        }

        Settings {
            SettingsWindow()
                .environment(settings)
                .environment(stats)
                .frame(width: 640, height: 500)
        }
    }
}
