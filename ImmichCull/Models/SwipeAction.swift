import SwiftUI

/// What a swipe can do; each direction is mapped to one of these in Settings.
enum SwipeAction: String, CaseIterable, Identifiable, Sendable {
    case trash
    case saveToAlbum
    case favorite
    case nextImage
    case previousImage
    case undo
    case disabled

    var id: String { rawValue }

    var label: String {
        switch self {
        case .trash: String(localized: "Trash")
        case .saveToAlbum: String(localized: "Add to Album")
        case .favorite: String(localized: "Favorite")
        case .nextImage: String(localized: "Next Image")
        case .previousImage: String(localized: "Previous Image")
        case .undo: String(localized: "Undo")
        case .disabled: String(localized: "Do Nothing")
        }
    }

    var systemImage: String {
        switch self {
        case .trash: "trash.fill"
        case .saveToAlbum: "rectangle.stack.badge.plus"
        case .favorite: "heart.fill"
        case .nextImage: "chevron.forward"
        case .previousImage: "chevron.backward"
        case .undo: "arrow.uturn.backward"
        case .disabled: "slash.circle"
        }
    }

    var tint: Color {
        switch self {
        case .trash: .red
        case .saveToAlbum: .blue
        case .favorite: .pink
        case .nextImage: .gray
        case .previousImage: .gray
        case .undo: .orange
        case .disabled: .gray
        }
    }
}
