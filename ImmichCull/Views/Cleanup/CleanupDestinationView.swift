import SwiftUI

/// Resolves a cleanup route to its screen, injecting the API client.
struct CleanupDestinationView: View {
    @Environment(SettingsStore.self) private var settings

    let route: CleanupRoute

    var body: some View {
        if let client = settings.client {
            switch route {
            case .duplicates:
                DuplicatesView(client: client)
            case .blurry:
                BlurScanView(client: client)
            case .screenshots:
                ScreenshotsView(client: client)
            case .receipts:
                ReceiptsView(client: client)
            }
        } else {
            ContentUnavailableView("Not connected", systemImage: "wifi.exclamationmark")
        }
    }
}
