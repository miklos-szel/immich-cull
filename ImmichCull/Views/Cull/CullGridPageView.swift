import SwiftUI

/// One screenful of the culling grid. Fixed layout, no scrolling — that's what
/// lets a selection drag work without competing with a scroll view for the
/// touch. Paging is horizontal, so a vertical drag is unambiguously selection.
struct CullGridPageView: View {
    let assets: [ImmichAsset]
    let selectedIDs: Set<String>
    let columns: Int
    let client: ImmichClient
    let onTap: (ImmichAsset) -> Void

    var body: some View {
        VStack(spacing: CullGridMetrics.spacing) {
            ForEach(rows, id: \.first?.id) { row in
                HStack(spacing: CullGridMetrics.spacing) {
                    ForEach(row) { asset in
                        CleanupGridCellView(
                            asset: asset,
                            isSelected: selectedIDs.contains(asset.id),
                            caption: nil,
                            client: client,
                            toggle: { onTap(asset) }
                        )
                        .dragSelectCell(id: asset.id)
                    }
                    // Keeps a short last row aligned with the ones above it
                    // instead of stretching its cells across the width.
                    if row.count < columns {
                        ForEach(0..<(columns - row.count), id: \.self) { _ in
                            Color.clear
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, CullGridMetrics.spacing)
    }

    private var rows: [[ImmichAsset]] {
        stride(from: 0, to: assets.count, by: columns).map {
            Array(assets[$0..<min($0 + columns, assets.count)])
        }
    }
}
