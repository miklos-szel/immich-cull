import SwiftUI

/// Scans the library for blurry / out-of-focus photos and offers to trash them.
struct BlurScanView: View {
    let client: ImmichClient

    @Environment(StatsStore.self) private var stats

    @State private var session: BlurScanSession?
    @State private var selectedIDs: Set<String> = []
    @State private var isConfirmingTrash = false
    @State private var isShowingActionError = false
    @State private var actionError: String?

    var body: some View {
        Group {
            if let session {
                switch session.phase {
                case .scanning:
                    BlurScanProgressView(scanned: session.scannedCount, total: session.totalCount)
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Scan failed", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Retry", action: restart)
                    }
                case .finished:
                    if session.results.isEmpty {
                        ContentUnavailableView {
                            Label("No photos to analyze", systemImage: "checkmark.seal")
                        } description: {
                            Text("The library has no images to scan.")
                        }
                    } else {
                        resultsGrid(session)
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Blurry Photos")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if let session, session.phase == .finished, !session.results.isEmpty {
                trashButton
            }
        }
        .alert("Couldn't move to trash", isPresented: $isShowingActionError) {
        } message: {
            Text(actionError ?? "")
        }
        .task { await startIfNeeded() }
    }

    private func resultsGrid(_ session: BlurScanSession) -> some View {
        ScrollView {
            Text("Sorted blurriest first. Likely-blurry photos are preselected.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.top, 4)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                ForEach(session.results) { result in
                    CleanupGridCellView(
                        asset: result.asset,
                        isSelected: selectedIDs.contains(result.id),
                        caption: result.score.formatted(.number.precision(.fractionLength(0))),
                        client: client,
                        toggle: { toggle(result) }
                    )
                    // Keyed on the result, not the asset: a photo can appear
                    // once per scan result and the selection follows that ID.
                    .dragSelectCell(id: result.id)
                }
            }
            .padding(.horizontal, 4)
        }
        .dragSelection(
            ids: session.results.map(\.id),
            isSelected: { selectedIDs.contains($0) },
            onPaint: setSelected
        )
    }

    private var trashButton: some View {
        Button(role: .destructive, action: confirmTrash) {
            Label("Move \(selectedIDs.count) to Trash", systemImage: "trash")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(selectedIDs.isEmpty)
        .padding()
        .background(.bar)
        .confirmationDialog(
            "Move \(selectedIDs.count) assets to the Immich trash?",
            isPresented: $isConfirmingTrash,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive, action: trashSelected)
        }
    }

    private func toggle(_ result: BlurResult) {
        if selectedIDs.contains(result.id) {
            selectedIDs.remove(result.id)
        } else {
            selectedIDs.insert(result.id)
        }
    }

    private func setSelected(_ id: String, _ isSelected: Bool) {
        if isSelected {
            selectedIDs.insert(id)
        } else {
            selectedIDs.remove(id)
        }
    }

    private func confirmTrash() {
        isConfirmingTrash = true
    }

    private func startIfNeeded() async {
        guard session == nil else { return }
        let newSession = BlurScanSession(client: client)
        session = newSession
        await newSession.start()
        selectedIDs = Set(
            newSession.results
                .filter { $0.score < BlurScanSession.blurryThreshold }
                .map(\.id)
        )
    }

    private func restart() {
        session = nil
        selectedIDs = []
        Task { await startIfNeeded() }
    }

    private func trashSelected() {
        let ids = selectedIDs
        Task {
            do {
                try await client.trashAssets(ids: Array(ids))
                stats.recordTrashed(count: ids.count)
                session?.removeResults(withIDs: ids)
                selectedIDs = []
            } catch {
                actionError = error.localizedDescription
                isShowingActionError = true
            }
        }
    }
}
