import SwiftUI

struct GeneralSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Review order") {
                Picker("Order", selection: $settings.order) {
                    ForEach(CullOrder.allCases) { Text($0.label).tag($0) }
                }
            }
            Section("What to include") {
                Toggle("Photos", isOn: $settings.includePhotos)
                Toggle("Videos", isOn: $settings.includeVideos)
            }
            Section("Appearance") {
                Picker("Theme", selection: $settings.appearance) {
                    ForEach(AppTheme.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section("Culling") {
                Toggle("Show file name and date", isOn: $settings.showCardInfo)
                Toggle("Also delete from this Mac's Photos", isOn: $settings.alsoDeleteFromPhotos)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
