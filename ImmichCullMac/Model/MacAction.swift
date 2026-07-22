import SwiftUI

/// The vocabulary of keyboard-bindable actions in the macOS app. Deck actions
/// reuse the same semantics as the iOS swipe actions; the rest are macOS-only
/// navigation commands. Each has a built-in default shortcut that the user can
/// override in Settings → Shortcuts.
enum MacAction: String, CaseIterable, Identifiable, Sendable {
    // Deck actions (dispatch straight into CullSession).
    case trash
    case nextImage
    case saveToAlbum
    case favorite
    case previousImage
    case undo
    // Navigation / global.
    case startCulling
    case openGrid
    case selectAll
    case showTrash

    var id: String { rawValue }

    /// The actions shown while culling, in footer order.
    static let deckActions: [MacAction] = [.trash, .nextImage, .saveToAlbum, .favorite, .previousImage, .undo]

    var label: String {
        switch self {
        case .trash: "Trash"
        case .nextImage: "Next Image"
        case .saveToAlbum: "Add to / Remove from Album"
        case .favorite: "Favorite"
        case .previousImage: "Previous Image"
        case .undo: "Undo"
        case .startCulling: "Start Culling"
        case .openGrid: "Show Grid"
        case .selectAll: "Select All"
        case .showTrash: "Show Trash Bin"
        }
    }

    var systemImage: String {
        switch self {
        case .trash: "trash"
        case .nextImage: "chevron.forward"
        case .saveToAlbum: "rectangle.stack.badge.plus"
        case .favorite: "heart"
        case .previousImage: "chevron.backward"
        case .undo: "arrow.uturn.backward"
        case .startCulling: "rectangle.portrait.on.rectangle.portrait.angled"
        case .openGrid: "square.grid.2x2"
        case .selectAll: "checkmark.circle"
        case .showTrash: "trash"
        }
    }

    var tint: Color {
        switch self {
        case .trash: .red
        case .saveToAlbum: .blue
        case .favorite: .pink
        case .undo: .orange
        default: .secondary
        }
    }

    /// The factory default shortcut. Users override these in Settings.
    var defaultShortcut: CullShortcut {
        switch self {
        case .trash: CullShortcut(key: "delete")
        case .nextImage: CullShortcut(key: "rightArrow")
        case .previousImage: CullShortcut(key: "leftArrow")
        case .favorite: CullShortcut(key: "f")
        case .saveToAlbum: CullShortcut(key: "a")
        case .undo: CullShortcut(key: "z", modifiers: Int(EventModifiers.command.rawValue))
        case .startCulling: CullShortcut(key: "return")
        case .openGrid: CullShortcut(key: "g")
        case .selectAll: CullShortcut(key: "a", modifiers: Int(EventModifiers.command.rawValue))
        case .showTrash: CullShortcut(key: "t", modifiers: Int(EventModifiers.command.rawValue))
        }
    }
}

extension SettingsStore {
    /// The effective shortcut for an action: the user's override, or the default.
    func shortcut(for action: MacAction) -> CullShortcut {
        keyBindings[action.rawValue] ?? action.defaultShortcut
    }

    /// Whether a key press should trigger this action, given the current binding.
    func matches(_ press: KeyPress, _ action: MacAction) -> Bool {
        shortcut(for: action).matches(press)
    }
}
