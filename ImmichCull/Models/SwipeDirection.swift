import Foundation

enum SwipeDirection: String, CaseIterable, Identifiable, Sendable {
    case up
    case down
    case left
    case right

    var id: String { rawValue }

    var label: String {
        switch self {
        case .up: String(localized: "Up")
        case .down: String(localized: "Down")
        case .left: String(localized: "Left")
        case .right: String(localized: "Right")
        }
    }

    var arrowSystemImage: String {
        switch self {
        case .up: "arrow.up"
        case .down: "arrow.down"
        case .left: "arrow.left"
        case .right: "arrow.right"
        }
    }
}
