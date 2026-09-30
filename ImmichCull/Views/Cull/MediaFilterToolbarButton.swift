import SwiftUI

/// Switches what the rest of the run offers: photos, videos, or both — and,
/// when `offersCulled` is given, whether already-culled photos are included.
///
/// Lives next to the trash button rather than in Settings because deciding you
/// only want to deal with videos, or want another pass over photos you already
/// culled, is something you realise partway through, not before. Settings still
/// supplies the starting values.
struct MediaFilterToolbarButton: View {
    let filter: MediaTypeFilter
    let select: (MediaTypeFilter) -> Void
    /// Nil hides the toggle.
    var offersCulled: Bool?
    var setOffersCulled: (Bool) -> Void = { _ in }
    /// While the culled photos are being fetched the toggle can't be flipped back.
    var isUpdatingCulled = false

    var body: some View {
        Menu {
            Picker("What to cull", selection: selection) {
                ForEach(MediaTypeFilter.allCases) { option in
                    Label(option.label, systemImage: option.systemImage).tag(option)
                }
            }
            .pickerStyle(.inline)
            if let offersCulled {
                Section("Already culled") {
                    Toggle(isOn: Binding(get: { offersCulled }, set: setOffersCulled)) {
                        Label("Offer Already-Culled Photos", systemImage: "checkmark.seal")
                    }
                    .disabled(isUpdatingCulled)
                    .accessibilityIdentifier("offersCulledToggle")
                }
            }
        } label: {
            Image(systemName: filter.systemImage)
                // Visible without opening the menu: the run is re-offering
                // photos you've culled before.
                .overlay(alignment: .bottomTrailing) {
                    if offersCulled == true {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 9))
                            .offset(x: 5, y: 4)
                    }
                }
        }
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("mediaFilterButton")
    }

    private var accessibilityText: String {
        offersCulled == true
            ? String(localized: "What to cull, \(filter.label), including already culled")
            : String(localized: "What to cull, \(filter.label)")
    }

    /// The session owns the value, so this is a write-through binding rather
    /// than local state that could drift from it.
    private var selection: Binding<MediaTypeFilter> {
        Binding(get: { filter }, set: select)
    }
}
