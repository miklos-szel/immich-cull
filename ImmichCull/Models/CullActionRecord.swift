import Foundation

struct CullActionRecord: Sendable {
    let asset: ImmichAsset
    let kind: CullActionKind
    /// Whether the asset already carried the mark tag before this action. With
    /// "Offer checked photos again" on, an already-culled asset can be swiped a
    /// second time; undoing that must leave the pre-existing tag alone rather
    /// than stripping it, both in the badge and on the server.
    var wasChecked = false
}
