import SwiftUI

/// Menu-bar commands. Culling shortcuts are handled in-view (and configured in
/// Settings → Shortcuts), so here we just drop the default "New" item this app
/// has no use for and point at where shortcuts live.
struct CullCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandGroup(replacing: .help) {
            SettingsLink {
                Text("Keyboard Shortcuts…")
            }
        }
    }
}
