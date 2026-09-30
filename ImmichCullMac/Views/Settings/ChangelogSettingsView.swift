import SwiftUI

struct ChangelogSettingsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("immich-cull for Mac").font(.headline)
                    Text("v\(Changelog.currentVersion)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                ForEach(Changelog.releases) { release in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Version \(release.version)").font(.headline)
                            Spacer()
                            Text(release.date).font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(release.changes, id: \.self) { change in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 4))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 5)
                                Text(change)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 8))
                }
            }
            .padding()
        }
    }
}
