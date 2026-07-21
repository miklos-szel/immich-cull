import SwiftUI

/// Opened from the logo on Home: what the app does, what's new, and where it
/// came from.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private static let githubURL = URL(string: "https://github.com/miklos-szel/immich-cull")!
    private static let immichURL = URL(string: "https://immich.app")!

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    section("How it works") {
                        Text(Self.overview)
                    }
                    changelog
                    links
                    section("Credits") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(Self.credits)
                            Text(Self.disclaimer)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .clipShape(.rect(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 2) {
                Text("immich-cull")
                    .font(.title2.bold())
                Text(Self.versionString)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var changelog: some View {
        section("What's New") {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Self.releases) { release in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Version \(release.version)")
                            .font(.headline)
                        ForEach(release.notes, id: \.self) { note in
                            Label(note, systemImage: "circle.fill")
                                .labelStyle(BulletLabelStyle())
                        }
                    }
                }
            }
        }
    }

    private var links: some View {
        section("Links") {
            VStack(alignment: .leading, spacing: 12) {
                Link(destination: Self.githubURL) {
                    Label("Source on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: Self.immichURL) {
                    Label("About Immich", systemImage: "photo.stack")
                }
            }
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.bold())
            content()
        }
    }

    // MARK: Content

    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(version) (\(build))"
    }

    private static let overview = """
    immich-cull is a fast, native way to tidy a self-hosted Immich library. Tap a \
    row — the entire roll, photos in no album, or any album — to open a grid of \
    everything in it. Press and drag to multi-select and move photos to the Immich \
    trash, or start the swipe deck to review one photo at a time: swipe to trash, \
    keep, favourite, or file into an album. Every change syncs to your Immich \
    server, and nothing is written to this device.
    """

    private static let credits = "Created by Miklos Szel. Built with SwiftUI, licensed under GPLv3."

    private static let disclaimer = """
    Unofficial and independent — not affiliated with, endorsed by, or sponsored by \
    the Immich project. "Immich" is the property of its respective owners.
    """

    private struct Release: Identifiable {
        let version: String
        let notes: [String]
        var id: String { version }
    }

    private static let releases: [Release] = [
        Release(version: "1.0", notes: [
            "Browse any album, the entire roll, or photos in no album as one continuous grid.",
            "Press-and-drag multi-select with edge auto-scroll; move selections to the Immich trash.",
            "Swipe deck to review one photo at a time — trash, keep, favourite, add to album.",
            "Video and Live Photo markers; Live Photos play on tap.",
            "Photos & videos filter, with paired Live Photo movies trashed together.",
        ]),
    ]
}

/// A left-aligned bullet for changelog lines.
private struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon
                .font(.system(size: 5))
                .foregroundStyle(.secondary)
            configuration.title
        }
    }
}

#Preview {
    AboutView()
}
