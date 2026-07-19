import SwiftUI

/// Transient error banner overlaid at the top of the cull screen.
struct ErrorBannerView: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.red.opacity(0.9), in: .capsule)
            .foregroundStyle(.white)
            .padding(.horizontal)
            .task {
                try? await Task.sleep(for: .seconds(4))
                dismiss()
            }
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}
