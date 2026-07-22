import SwiftUI

extension CullShortcut {
    /// The named special keys we round-trip through `key`. Anything else is a
    /// single literal character.
    private static let specialKeys: [String: KeyEquivalent] = [
        "leftArrow": .leftArrow,
        "rightArrow": .rightArrow,
        "upArrow": .upArrow,
        "downArrow": .downArrow,
        "delete": .delete,
        "return": .return,
        "space": .space,
        "escape": .escape,
        "tab": .tab,
    ]

    var eventModifiers: EventModifiers { EventModifiers(rawValue: modifiers) }

    var keyEquivalent: KeyEquivalent? {
        if let special = Self.specialKeys[key] { return special }
        guard let character = key.first, key.count == 1 else { return nil }
        return KeyEquivalent(character)
    }

    /// A SwiftUI `KeyboardShortcut` for menu items, or nil for an unmappable key.
    var keyboardShortcut: KeyboardShortcut? {
        guard let keyEquivalent else { return nil }
        return KeyboardShortcut(keyEquivalent, modifiers: eventModifiers)
    }

    /// The modifier flags we compare on (ignore capsLock/function/numericPad).
    private static let comparedModifiers: EventModifiers = [.command, .option, .control, .shift]

    /// Whether a live key press matches this shortcut.
    func matches(_ press: KeyPress) -> Bool {
        let pressMods = press.modifiers.intersection(Self.comparedModifiers)
        let ownMods = eventModifiers.intersection(Self.comparedModifiers)
        guard pressMods == ownMods else { return false }
        if let keyEquivalent, press.key == keyEquivalent { return true }
        // Fall back to the typed character for letter/number keys (robust to
        // layout quirks where `press.key` and the literal differ).
        if key.count == 1, Self.specialKeys[key] == nil {
            return press.characters.lowercased() == key.lowercased()
        }
        return false
    }

    /// Builds a shortcut from a captured key press (for the recorder UI).
    /// Returns nil for a bare modifier press (no usable key).
    init?(press: KeyPress) {
        let mods = press.modifiers.intersection(Self.comparedModifiers)
        let token: String
        switch press.key {
        case .leftArrow: token = "leftArrow"
        case .rightArrow: token = "rightArrow"
        case .upArrow: token = "upArrow"
        case .downArrow: token = "downArrow"
        case .delete: token = "delete"
        case .return: token = "return"
        case .space: token = "space"
        case .escape: token = "escape"
        case .tab: token = "tab"
        default:
            let char = press.characters.trimmingCharacters(in: .whitespaces)
            guard let first = char.first else { return nil }
            token = String(first).lowercased()
        }
        self.init(key: token, modifiers: Int(mods.rawValue))
    }

    /// Human-readable label, e.g. "⌘Z", "←", "⌫", "F".
    var displayString: String {
        var parts = ""
        let mods = eventModifiers
        if mods.contains(.control) { parts += "⌃" }
        if mods.contains(.option) { parts += "⌥" }
        if mods.contains(.shift) { parts += "⇧" }
        if mods.contains(.command) { parts += "⌘" }
        parts += keyLabel
        return parts
    }

    private var keyLabel: String {
        switch key {
        case "leftArrow": "←"
        case "rightArrow": "→"
        case "upArrow": "↑"
        case "downArrow": "↓"
        case "delete": "⌫"
        case "return": "↩"
        case "space": "␣"
        case "escape": "⎋"
        case "tab": "⇥"
        default: key.uppercased()
        }
    }
}

extension View {
    /// Applies a keyboard shortcut from a `CullShortcut`, if it maps to one.
    @ViewBuilder
    func keyboardShortcut(_ shortcut: CullShortcut?) -> some View {
        if let shortcut, let ks = shortcut.keyboardShortcut {
            self.keyboardShortcut(ks.key, modifiers: ks.modifiers)
        } else {
            self
        }
    }
}
