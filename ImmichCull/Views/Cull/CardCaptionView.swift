import SwiftUI

/// Filename and capture date under the current card.
struct CardCaptionView: View {
    let asset: ImmichAsset

    var body: some View {
        VStack(spacing: 2) {
            Text(asset.originalFileName)
                .font(.subheadline)
                .lineLimit(1)
            if let takenAt = asset.takenAt {
                Text(takenAt, format: .dateTime.day().month().year().hour().minute())
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
