import SwiftUI

struct ServerSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(StatsStore.self) private var stats

    @State private var status: String?
    @State private var checking = false

    var body: some View {
        Form {
            Section("Server") {
                LabeledContent("Address", value: settings.serverURLString.isEmpty ? "—" : settings.serverURLString)
                Button {
                    checkConnection()
                } label: {
                    if checking { ProgressView().controlSize(.small) } else { Text("Check Connection") }
                }
                if let status {
                    Text(status).font(.callout).foregroundStyle(.secondary)
                }
            }

            Section("Lifetime totals") {
                LabeledContent("Trashed", value: "\(stats.trashed)")
                LabeledContent("Skipped", value: "\(stats.skipped)")
                LabeledContent("Added to album", value: "\(stats.savedToAlbum)")
                LabeledContent("Favorited", value: "\(stats.favorited)")
            }

            Section {
                Button("Sign Out", role: .destructive) {
                    settings.signOut()
                }
            } footer: {
                Text("Forgets the server address and API key on this Mac.")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func checkConnection() {
        guard let client = settings.client, let url = settings.serverURL else {
            status = "Not configured."
            return
        }
        checking = true
        status = nil
        Task {
            let alive = await ImmichClient.ping(serverURL: url)
            if !alive {
                status = "Couldn't reach the server."
            } else if let user = try? await client.currentUser() {
                status = "Connected as \(user.name)."
            } else {
                status = "Reachable, but the API key was rejected."
            }
            checking = false
        }
    }
}
