import SwiftUI

struct BlurScanProgressView: View {
    let scanned: Int
    let total: Int

    var body: some View {
        VStack(spacing: 12) {
            ProgressView(value: total > 0 ? Double(scanned) / Double(total) : 0)
                .frame(maxWidth: 240)
            Text("Analyzing \(scanned) of \(total)…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding()
    }
}
