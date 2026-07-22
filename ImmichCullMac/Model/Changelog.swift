import Foundation

/// One released version and what changed in it. Newest first in `Changelog`.
struct ReleaseNote: Identifiable {
    let version: String
    let date: String
    let changes: [String]
    var id: String { version }
}

enum Changelog {
    /// The app's marketing version, read from the bundle.
    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    static let releases: [ReleaseNote] = [
        ReleaseNote(version: "1.0.1", date: "2026-07-22", changes: [
            "Fixed a crash when a video appeared in the culling deck.",
            "The culling window can now be resized freely.",
            "Press Space to play or pause a video while culling.",
        ]),
        ReleaseNote(version: "1.0", date: "2026-07-22", changes: [
            "First macOS release — keyboard-first culling sharing the iOS app's engine.",
            "Split-view home over the whole library, the unsorted pile, or any album, with a trash bin.",
            "Browse grid with macOS-Photos multi-select (click, ⌘/⇧-click, drag-marquee, ⌘A, arrow keys) and a configurable thumbnail size.",
            "Configurable keyboard shortcuts for every action, in Settings → Shortcuts.",
            "Removes culled items from this Mac's Photos library.",
        ]),
    ]
}
