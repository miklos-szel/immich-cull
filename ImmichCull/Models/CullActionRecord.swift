import Foundation

struct CullActionRecord: Sendable {
    /// Identity of this one swipe. The same asset can be acted on again after a
    /// back-step, so a failure report must name the record, not just the asset.
    let id = UUID()
    let asset: ImmichAsset
    let kind: CullActionKind
    /// Whether the asset already carried the mark tag before this action. With
    /// "Offer checked photos again" on, an already-culled asset can be swiped a
    /// second time; undoing that must leave the pre-existing tag alone rather
    /// than stripping it, both in the badge and on the server.
    var wasChecked = false
    /// The action last applied to this asset before this one, if any — set
    /// when a back-step re-showed the asset and it was swiped again. Undo puts
    /// it back, since that earlier action is still in effect on the server.
    var priorAction: CullActionKind?
}
