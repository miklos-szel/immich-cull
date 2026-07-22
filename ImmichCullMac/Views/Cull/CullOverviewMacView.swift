import SwiftUI

/// A grid overview of what's left in the deck. Clicking a photo jumps the deck
/// to it (preceding photos move to the end — nothing is skipped for good).
struct CullOverviewMacView: View {
    let session: CullSession
    let onClose: () -> Void

    @Environment(SettingsStore.self) private var settings

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(session.queue.count) remaining").font(.headline)
                Spacer()
                Button("Close", action: onClose).keyboardShortcut(.cancelAction)
            }
            .padding(12)
            Divider()
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: settings.thumbnailSize), spacing: 6)], spacing: 6) {
                    ForEach(session.queue) { asset in
                        Button {
                            session.jump(toID: asset.id)
                            onClose()
                        } label: {
                            GridCellView(
                                asset: asset,
                                client: settings.client,
                                apiKey: settings.apiKey,
                                state: session.state(for: asset),
                                isSelected: asset.id == session.current?.id,
                                isCursor: false)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
            }
        }
    }
}
