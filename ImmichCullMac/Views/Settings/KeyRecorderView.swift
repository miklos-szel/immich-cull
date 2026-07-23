import SwiftUI

/// A click-to-record control that captures the next key press and stores it as
/// the binding for `action`. Esc cancels; there's no third-party dependency.
struct KeyRecorderView: View {
    let action: MacAction

    @Environment(SettingsStore.self) private var settings
    @State private var recording = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Button {
                recording.toggle()
                focused = recording
            } label: {
                Text(recording ? "Press a key…" : settings.shortcut(for: action).displayString)
                    .font(.body.monospaced())
                    .frame(minWidth: 96)
            }
            .buttonStyle(.bordered)
            .tint(recording ? .accentColor : nil)
            .focusable(recording)
            .focused($focused)
            .onKeyPress(phases: .down) { press in
                guard recording else { return .ignored }
                if press.key == .escape {
                    recording = false
                    return .handled
                }
                if let shortcut = CullShortcut(press: press) {
                    var bindings = settings.keyBindings
                    // If another action already resolves to this shortcut (via an
                    // override or its default), hand it this action's old binding
                    // rather than leaving it silently shadowed and dead.
                    if let conflicting = MacAction.allCases.first(where: {
                        $0 != action && settings.shortcut(for: $0) == shortcut
                    }) {
                        bindings[conflicting.rawValue] = settings.shortcut(for: action)
                    }
                    bindings[action.rawValue] = shortcut
                    settings.keyBindings = bindings
                }
                recording = false
                return .handled
            }

            if settings.keyBindings[action.rawValue] != nil {
                Button {
                    var bindings = settings.keyBindings
                    bindings.removeValue(forKey: action.rawValue)
                    settings.keyBindings = bindings
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .help("Reset to default")
            }
        }
    }
}
