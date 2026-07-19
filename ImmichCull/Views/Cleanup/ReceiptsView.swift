import SwiftUI

struct ReceiptsView: View {
    let client: ImmichClient

    var body: some View {
        CleanupSelectionGridView(
            title: String(localized: "Receipts & Bills"),
            emptyDescription: String(localized: "No receipt-like photos found. This finder uses Immich smart search, which needs machine learning enabled on the server."),
            headerNote: String(localized: "Best smart-search matches first — review before trashing."),
            preselectAll: false,
            client: client,
            loadAssets: loadReceipts
        )
    }

    private func loadReceipts() async throws -> [ImmichAsset] {
        try await client
            .smartSearchAssets(query: "a photo of a paper receipt, bill or invoice", limit: 60)
            .filter { $0.type == .image }
    }
}
