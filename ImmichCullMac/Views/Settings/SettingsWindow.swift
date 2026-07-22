import SwiftUI

/// The tabbed Settings window (⌘,). Keyboard shortcuts get their own tab.
struct SettingsWindow: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            ShortcutsSettingsView()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            DisplaySettingsView()
                .tabItem { Label("Display", systemImage: "square.grid.2x2") }
            TagsSettingsView()
                .tabItem { Label("Tags", systemImage: "tag") }
            AlbumSettingsView()
                .tabItem { Label("Album", systemImage: "rectangle.stack") }
            ServerSettingsView()
                .tabItem { Label("Server", systemImage: "server.rack") }
        }
    }
}
