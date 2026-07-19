import Foundation

enum CullActionKind: Sendable {
    /// Move the asset to the Immich trash.
    case trash
    /// Move on to the next asset, tagging it as reviewed so it isn't offered again.
    case skip
    /// Add the asset to the configured album (and mark checked).
    case saveToAlbum
    /// Mark the asset as a favorite (and mark checked).
    case favorite
}
