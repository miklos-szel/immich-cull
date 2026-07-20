import SwiftUI

/// Switches what the rest of the run offers: photos, videos, or both.
///
/// Lives next to the trash button rather than in Settings because deciding you
/// only want to deal with videos is something you realise partway through a
/// run, not before it. Settings still supplies the starting value.
struct MediaFilterToolbarButton: View {
    let filter: MediaTypeFilter
    let select: (MediaTypeFilter) -> Void

    var body: some View {
        Menu {
            Picker("What to cull", selection: selection) {
                ForEach(MediaTypeFilter.allCases) { option in
                    Label(option.label, systemImage: option.systemImage).tag(option)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: filter.systemImage)
        }
        .accessibilityLabel("What to cull, \(filter.label)")
        .accessibilityIdentifier("mediaFilterButton")
    }

    /// The session owns the value, so this is a write-through binding rather
    /// than local state that could drift from it.
    private var selection: Binding<MediaTypeFilter> {
        Binding(get: { filter }, set: select)
    }
}
