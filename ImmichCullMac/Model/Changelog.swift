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
        ReleaseNote(version: "1.1", date: "2026-09-30", changes: [
            "Turn “offer already-culled photos” on or off from the filter menu, in the deck and the grid.",
            "Libraries over 5,000 items no longer stall once the first 5,000 are culled.",
            "Trashed items are removed from Photos when you leave culling, even mid-run.",
            "A trash or undo the server rejects is rolled back instead of silently counted.",
            "Safer Photos matching: a photo with no capture date is never matched by filename alone.",
            "Restoring a Live Photo from the trash restores its motion too.",
            "Nested tags (e.g. Trips/culled) are matched and written correctly.",
            "The grid shows album-membership badges, follows the review order, and names the active filter.",
            "Add selected photos to an album straight from the browse grid.",
            "Search field to narrow down the album list in the sidebar.",
            "Press Space in the grid to start culling from the focused photo.",
            "Returning from the deck scrolls the grid back to where you were, not the top.",
        ]),
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
