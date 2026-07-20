import Foundation

enum CullActionKind: Sendable {
    /// Move the asset to the Immich trash.
    case trash
    /// Move on to the next asset, tagging it as reviewed so it isn't offered again.
    case skip
    /// Add the asset to the configured album (and mark checked).
    case saveToAlbum
    /// Take the asset back out of the configured album (and mark checked).
    /// The counterpart to `saveToAlbum`: the same swipe does whichever of the
    /// two the asset's current state calls for.
    case removeFromAlbum
    /// Mark the asset as a favorite (and mark checked).
    case favorite
    /// Un-favorite the asset (and mark checked). Counterpart to `favorite`.
    case unfavorite
}
