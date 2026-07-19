import SwiftUI

/// Lifetime culling counters plus the server's current trash contents.
struct StatsSectionView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(StatsStore.self) private var stats

    @State private var trashStats: AssetStats?

    var body: some View {
        Section {
            LabeledContent("Deleted with this app") {
                Text(stats.trashed, format: .number)
            }
            LabeledContent("Reviewed") {
                Text(stats.skipped, format: .number)
            }
            LabeledContent("Added to album") {
                Text(stats.savedToAlbum, format: .number)
            }
            LabeledContent("Favorited") {
                Text(stats.favorited, format: .number)
            }
            LabeledContent("In Immich trash now") {
                if let trashStats {
                    Text("\(trashStats.images) photos, \(trashStats.videos) videos")
                } else {
                    Text(verbatim: "—")
                        .foregroundStyle(.tertiary)
                }
            }
        } header: {
            Text("Stats")
        } footer: {
            Text("Trashed items stay recoverable in Immich until the trash is emptied.")
        }
        .task {
            trashStats = try? await settings.client?.trashStatistics()
        }
    }
}
