import SwiftUI

/// First-run connection screen: server URL + API key, with a live test.
struct ConnectionView: View {
    @Environment(SettingsStore.self) private var settings

    @State private var urlText = ""
    @State private var keyText = ""
    @State private var isTesting = false
    @State private var status: Status?

    private enum Status: Equatable {
        case success(String)
        case failure(String)
    }

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Image(systemName: "photo.stack")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                Text("Connect to Immich")
                    .font(.title2.bold())
                Text("Enter your server address and an API key from Immich → Account Settings → API Keys.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            Form {
                TextField("Server URL", text: $urlText, prompt: Text("https://immich.example.com"))
                    .textContentType(.URL)
                SecureField("API Key", text: $keyText)
            }
            .formStyle(.grouped)
            .frame(maxWidth: 460)

            if let status {
                Label {
                    Text(statusMessage(status))
                } icon: {
                    Image(systemName: isSuccess(status) ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                }
                .foregroundStyle(isSuccess(status) ? .green : .red)
                .font(.callout)
            }

            Button(action: connect) {
                if isTesting {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Connect")
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(isTesting || !canConnect)
            .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            urlText = settings.serverURLString
            keyText = settings.apiKey
        }
    }

    private var canConnect: Bool {
        !urlText.trimmingCharacters(in: .whitespaces).isEmpty && !keyText.isEmpty
    }

    private func isSuccess(_ status: Status) -> Bool {
        if case .success = status { return true }
        return false
    }

    private func statusMessage(_ status: Status) -> String {
        switch status {
        case .success(let message), .failure(let message): message
        }
    }

    private func connect() {
        let normalized = normalizedURLString(urlText)
        guard let url = URL(string: normalized), url.scheme != nil, url.host() != nil else {
            status = .failure("That doesn't look like a valid URL.")
            return
        }
        isTesting = true
        status = nil
        Task {
            let alive = await ImmichClient.ping(serverURL: url)
            guard alive else {
                isTesting = false
                status = .failure("Couldn't reach the server. Check the address and that Immich is running.")
                return
            }
            let client = ImmichClient(serverURL: url, apiKey: keyText)
            do {
                let user = try await client.currentUser()
                // Commit only after a verified round-trip.
                settings.serverURLString = normalized
                settings.apiKey = keyText
                isTesting = false
                status = .success("Connected as \(user.name).")
            } catch {
                isTesting = false
                status = .failure("The server is reachable but rejected the API key.")
            }
        }
    }

    private func normalizedURLString(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("/") { trimmed = String(trimmed.dropLast()) }
        if !trimmed.contains("://") { trimmed = "http://" + trimmed }
        return trimmed
    }
}
