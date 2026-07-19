import SwiftUI

struct ScreenshotsView: View {
    let client: ImmichClient

    var body: some View {
        CleanupSelectionGridView(
            title: String(localized: "Screenshots"),
            emptyDescription: String(localized: "No screenshots detected in your library."),
            headerNote: nil,
            preselectAll: true,
            client: client,
            loadAssets: loadScreenshots
        )
    }

    private func loadScreenshots() async throws -> [ImmichAsset] {
        try await client
            .fetchAssets(albumIDs: nil, tagIDs: nil, order: "desc", limit: 2000)
            .filter(ScreenshotDetector.isScreenshot)
    }
}
