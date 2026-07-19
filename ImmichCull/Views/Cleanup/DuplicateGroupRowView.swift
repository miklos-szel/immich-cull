import SwiftUI

struct DuplicateGroupRowView: View {
    let group: DuplicateGroup
    @Binding var selectedIDs: Set<String>
    let client: ImmichClient

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("^[\(group.assets.count) copy](inflect: true)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(group.assets) { asset in
                        CleanupGridCellView(
                            asset: asset,
                            isSelected: selectedIDs.contains(asset.id),
                            caption: nil,
                            client: client,
                            toggle: { toggle(asset) }
                        )
                        .frame(width: 96)
                        .dragSelectCell(id: asset.id)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .dragSelection(
                isSelected: { selectedIDs.contains($0) },
                onPaint: setSelected
            )
        }
        .padding(.vertical, 4)
    }

    private func setSelected(_ id: String, _ isSelected: Bool) {
        if isSelected {
            selectedIDs.insert(id)
        } else {
            selectedIDs.remove(id)
        }
    }

    private func toggle(_ asset: ImmichAsset) {
        if selectedIDs.contains(asset.id) {
            selectedIDs.remove(asset.id)
        } else {
            selectedIDs.insert(asset.id)
        }
    }
}
