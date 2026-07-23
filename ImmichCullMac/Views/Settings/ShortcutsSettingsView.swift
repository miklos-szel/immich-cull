import SwiftUI

struct ShortcutsSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        Form {
            Section("While culling") {
                ForEach(MacAction.deckActions) { row($0) }
            }
            Section("In the grid") {
                row(.startCulling)
                row(.selectAll)
                row(.openGrid)
            }
            Section("Anywhere") {
                row(.showTrash)
            }
            Section {
                Button("Reset All to Defaults", role: .destructive) {
                    settings.keyBindings = [:]
                }
            } footer: {
                Text("Click a shortcut, then press the key combination you want. Press Esc to cancel.")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func row(_ action: MacAction) -> some View {
        LabeledContent {
            KeyRecorderView(action: action)
        } label: {
            Label(action.label, systemImage: action.systemImage)
        }
    }
}
