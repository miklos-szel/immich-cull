import Foundation

struct DuplicateGroup: Codable, Identifiable, Sendable {
    let duplicateId: String
    let assets: [ImmichAsset]
    let suggestedKeepAssetIds: [String]?

    var id: String { duplicateId }

    /// Assets preselected for trashing: everything Immich doesn't suggest keeping.
    var defaultTrashIDs: [String] {
        let assetIDs = Set(assets.map(\.id))
        // Suggested IDs can reference assets no longer in the group; if none of
        // them survive, keep the first asset so we never preselect everything.
        let suggested = Set(suggestedKeepAssetIds ?? []).intersection(assetIDs)
        let keep = suggested.isEmpty ? Set(assets.prefix(1).map(\.id)) : suggested
        return assets.map(\.id).filter { !keep.contains($0) }
    }
}
