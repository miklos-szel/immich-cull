import Foundation

/// A persisted keyboard shortcut: a key token plus modifier flags. Kept in the
/// shared layer (Foundation-only) so `SettingsStore` can store it on every
/// platform; the macOS target maps it to a SwiftUI `KeyboardShortcut`.
///
/// `key` is either a single character ("f", "a", "z") or one of the named
/// special-key tokens the macOS target understands ("leftArrow", "rightArrow",
/// "upArrow", "downArrow", "delete", "return", "space", "escape"). `modifiers`
/// mirrors SwiftUI `EventModifiers.rawValue` so the mapping is lossless.
struct CullShortcut: Codable, Hashable, Sendable {
    var key: String
    var modifiers: Int

    init(key: String, modifiers: Int = 0) {
        self.key = key
        self.modifiers = modifiers
    }
}
