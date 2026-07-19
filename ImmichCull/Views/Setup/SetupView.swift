import SwiftUI

struct SetupView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var discovery = ServerDiscovery()
    @State private var urlString = ""
    @State private var apiKey = ""
    @State private var isConnecting = false
    @State private var connectionError: String?
    @State private var isShowingError = false

    var body: some View {
        NavigationStack {
            Form {
                discoverySection
                credentialsSection
                connectSection
            }
            .navigationTitle("Connect to Immich")
            .task { await discovery.scan() }
            .alert("Connection failed", isPresented: $isShowingError) {
            } message: {
                Text(connectionError ?? "")
            }
        }
    }

    private var discoverySection: some View {
        Section {
            ForEach(discovery.servers) { server in
                Button {
                    urlString = server.url.absoluteString
                } label: {
                    Label(server.url.absoluteString, systemImage: "server.rack")
                }
            }
            if discovery.isScanning {
                HStack {
                    ProgressView()
                    Text("Scanning local network…")
                        .foregroundStyle(.secondary)
                }
            } else if discovery.servers.isEmpty {
                Text("No Immich servers found on this network.")
                    .foregroundStyle(.secondary)
            }
            if !discovery.isScanning {
                Button("Scan Again", systemImage: "arrow.clockwise", action: rescan)
            }
        } header: {
            Text("Discovered servers")
        } footer: {
            Text("Looks for Immich on port 2283 across your local network. Tap a result to use it.")
        }
    }

    private var credentialsSection: some View {
        Section {
            TextField("Server URL", text: $urlString, prompt: Text(verbatim: "http://192.168.1.10:2283"))
                .keyboardType(.URL)
                .textContentType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("serverURLField")
            // A plain TextField: SecureField triggers the iOS "Save Password"
            // prompt, which is wrong for an API key and blocks the UI.
            TextField("API key", text: $apiKey)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .font(.callout.monospaced())
                .accessibilityIdentifier("apiKeyField")
        } header: {
            Text("Server")
        } footer: {
            Text("Create an API key in the Immich web app under Account Settings → API Keys.")
        }
    }

    private var connectSection: some View {
        Section {
            Button(action: connect) {
                if isConnecting {
                    HStack {
                        ProgressView()
                        Text("Connecting…")
                    }
                } else {
                    Text("Connect")
                }
            }
            .disabled(isConnecting || urlString.isEmpty || apiKey.isEmpty)
        }
    }

    private func rescan() {
        Task { await discovery.scan() }
    }

    private func connect() {
        Task { await validateAndSave() }
    }

    private func validateAndSave() async {
        isConnecting = true
        defer { isConnecting = false }

        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmedURL.hasSuffix("/") ? String(trimmedURL.dropLast()) : trimmedURL
        guard let url = URL(string: normalized), url.scheme != nil, url.host() != nil else {
            connectionError = ImmichError.invalidURL.localizedDescription
            isShowingError = true
            return
        }

        let client = ImmichClient(serverURL: url, apiKey: trimmedKey)
        do {
            _ = try await client.currentUser()
            settings.serverURLString = normalized
            settings.apiKey = trimmedKey
        } catch {
            connectionError = error.localizedDescription
            isShowingError = true
        }
    }
}

#Preview {
    SetupView()
        .environment(SettingsStore())
}
