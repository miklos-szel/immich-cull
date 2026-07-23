import SwiftUI

struct DisplaySettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Thumbnail size") {
                Slider(value: $settings.thumbnailSize, in: 80...260, step: 10) {
                    Text("Size")
                } minimumValueLabel: {
                    Image(systemName: "photo").imageScale(.small)
                } maximumValueLabel: {
                    Image(systemName: "photo").imageScale(.large)
                }
                LabeledContent("Minimum cell width", value: "\(Int(settings.thumbnailSize)) pt")

                // Live preview of the resulting density.
                let columns = [GridItem(.adaptive(minimum: settings.thumbnailSize / 3), spacing: 3)]
                LazyVGrid(columns: columns, spacing: 3) {
                    ForEach(0..<24, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.quaternary)
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
                .frame(height: 120)
                .clipped()
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
