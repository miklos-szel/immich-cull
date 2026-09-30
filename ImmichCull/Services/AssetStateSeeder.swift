import Foundation

/// Works out what is already true of a set of assets — favourited, in the
/// destination album, already culled — so the deck and every browse grid show
/// the same badges from the same rules.
///
/// Before this existed each screen seeded its own, and they disagreed: the
/// browse grids never looked up album membership, so a photo showed "in album"
/// in the deck and not in the grid it was launched from.
enum AssetStateSeeder {
    /// Every asset carrying any of the "already culled" tags, matched by full
    /// tag `value`. `alsoTagID` is folded in unconditionally: an asset this app
    /// marked must count as culled even if its tag isn't in the list.
    static func checkedIDs(client: ImmichClient, tagValues: [String],
                           alsoTagID: String? = nil) async throws -> Set<String> {
        let all = try await client.tags()
        var tagIDs = Set(all.filter { tagValues.contains($0.value) }.map(\.id))
        if let alsoTagID { tagIDs.insert(alsoTagID) }
        return try await client.assetIDs(withAnyTagID: Array(tagIDs))
    }

    /// Members of `albumID`, uncapped: a cap here silently reports the rest of
    /// a large album as "not in the album", which then makes the toggling
    /// swipe *add* what is already there.
    static func albumMemberIDs(client: ImmichClient, albumID: String) async throws -> Set<String> {
        guard !albumID.isEmpty else { return [] }
        let members = try await client.fetchAssets(albumIDs: [albumID], tagIDs: nil, order: "desc",
                                                   limit: .max, withExif: false)
        return Set(members.map(\.id))
    }

    static func states(for assets: [ImmichAsset], checkedIDs: Set<String>,
                       albumMemberIDs: Set<String>) -> [String: AssetCullState] {
        assets.reduce(into: [:]) { states, asset in
            states[asset.id] = AssetCullState(
                isFavorite: asset.isFavorite ?? false,
                isInDestinationAlbum: albumMemberIDs.contains(asset.id),
                isChecked: checkedIDs.contains(asset.id)
            )
        }
    }

    /// The whole lookup for a browse grid. Each half degrades to "none" on
    /// failure: a badge missing information is better than no grid.
    @MainActor
    static func seed(_ assets: [ImmichAsset], client: ImmichClient,
                     settings: SettingsStore) async -> [String: AssetCullState] {
        async let checked = try? checkedIDs(client: client,
                                            tagValues: settings.checkedTagNames + [settings.markTagName])
        async let members = try? albumMemberIDs(client: client, albumID: settings.destinationAlbumID)
        return states(for: assets, checkedIDs: await checked ?? [], albumMemberIDs: await members ?? [])
    }
}
