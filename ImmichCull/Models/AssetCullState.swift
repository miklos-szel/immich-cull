import Foundation

/// What has already happened to an asset, as far as this session knows.
///
/// The server's own copy of this (`ImmichAsset.isFavorite`, `.tags`) is a
/// snapshot from the search that loaded the queue, and goes stale the moment a
/// swipe changes anything. The session tracks it separately so the badges — and
/// the decision of whether a down-swipe adds or removes — reflect the swipe you
/// just made rather than the state at load.
struct AssetCullState: Equatable, Sendable {
    var isFavorite = false
    var isInDestinationAlbum = false
    /// Carries one of the tags configured as meaning "already culled".
    var isChecked = false

    var isEmpty: Bool { !isFavorite && !isInDestinationAlbum && !isChecked }
}
