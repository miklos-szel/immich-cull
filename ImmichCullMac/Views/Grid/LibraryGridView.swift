import SwiftUI
import AppKit

/// Full browse grid for a source, with macOS-Photos-style multi-select:
/// click selects one, Cmd-click toggles, Shift-click ranges, drag marquee, and
/// arrow keys move a cursor. Selected assets can be trashed in bulk or used to
/// start the culling deck.
struct LibraryGridView: View {
    let selection: AlbumSelection
    let onStartCull: (_ startAssetID: String?) -> Void
    let onTrashed: () -> Void

    @Environment(SettingsStore.self) private var settings
    @Environment(StatsStore.self) private var stats

    @State private var allAssets: [ImmichAsset] = []
    @State private var states: [String: AssetCullState] = [:]
    @State private var filter: MediaTypeFilter = .all
    @State private var didSetInitialFilter = false

    @State private var phase: Phase = .loading
    @State private var selectedIDs: Set<String> = []
    /// Anchor for Shift-range selection and arrow extension.
    @State private var anchorID: String?

    // Marquee drag state, in the "grid" coordinate space.
    @State private var marqueeStart: CGPoint?
    @State private var marqueeRect: CGRect?
    @State private var marqueeBase: Set<String> = []
    @State private var cellFrames: [String: CGRect] = [:]

    @State private var columnCount = 1
    @State private var confirmTrash = false
    @State private var trashError: String?
    @FocusState private var gridFocused: Bool

    private enum Phase: Equatable { case loading, loaded, empty, failed(String) }
    private let spacing: CGFloat = 6

    private var assets: [ImmichAsset] {
        allAssets.filter { filter.includes($0.type) }
    }

    var body: some View {
        content
            .toolbar { toolbarContent }
            .task(id: selection.id) { await load() }
            .onChange(of: filter) { _, _ in
                // Drop now-hidden assets from the selection so a hidden asset
                // can't inflate the count or get trashed off-screen.
                selectedIDs.formIntersection(Set(assets.map(\.id)))
            }
            .alert("Couldn't move to trash", isPresented: Binding(
                get: { trashError != nil }, set: { if !$0 { trashError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(trashError ?? "")
            }
            .confirmationDialog(trashPrompt, isPresented: $confirmTrash, titleVisibility: .visible) {
                Button("Move to Trash", role: .destructive, action: trashSelected)
                Button("Cancel", role: .cancel) {}
            }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't load photos", systemImage: "photo.badge.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Retry") { Task { await load() } }
            }
        case .empty:
            ContentUnavailableView("Nothing here", systemImage: "photo",
                                   description: Text("No \(filter.label.lowercased()) in this source."))
        case .loaded:
            grid
        }
    }

    private var grid: some View {
        GeometryReader { proxy in
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: settings.thumbnailSize), spacing: spacing)],
                          spacing: spacing) {
                    ForEach(assets) { asset in
                        GridCellView(
                            asset: asset,
                            client: settings.client,
                            apiKey: settings.apiKey,
                            state: states[asset.id] ?? AssetCullState(),
                            isSelected: selectedIDs.contains(asset.id),
                            isCursor: anchorID == asset.id
                        )
                        .background(cellFrameReader(for: asset.id))
                        .onTapGesture { handleClick(asset) }
                    }
                }
                .padding(spacing)
            }
            .coordinateSpace(.named("grid"))
            .overlay(alignment: .topLeading) { marqueeOverlay }
            .gesture(marqueeGesture)
            .onPreferenceChange(CellFrameKey.self) { cellFrames = $0 }
            .onChange(of: proxy.size.width) { _, width in
                columnCount = max(1, Int((width + spacing) / (settings.thumbnailSize + spacing)))
            }
            .onAppear {
                columnCount = max(1, Int((proxy.size.width + spacing) / (settings.thumbnailSize + spacing)))
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($gridFocused)
        .onAppear { gridFocused = true }
        .onKeyPress(phases: .down) { handleKey($0) }
        .safeAreaInset(edge: .bottom) { bottomBar }
    }

    // MARK: Cell frame collection

    private func cellFrameReader(for id: String) -> some View {
        GeometryReader { geo in
            Color.clear.preference(key: CellFrameKey.self,
                                   value: [id: geo.frame(in: .named("grid"))])
        }
    }

    // MARK: Marquee

    @ViewBuilder
    private var marqueeOverlay: some View {
        if let rect = marqueeRect {
            Rectangle()
                .fill(Color.accentColor.opacity(0.15))
                .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 1))
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .allowsHitTesting(false)
        }
    }

    private var marqueeGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named("grid"))
            .onChanged { value in
                if marqueeStart == nil {
                    marqueeStart = value.startLocation
                    // Additive when a modifier is held at drag start.
                    let mods = NSEvent.modifierFlags
                    marqueeBase = (mods.contains(.command) || mods.contains(.shift)) ? selectedIDs : []
                }
                let rect = CGRect(start: marqueeStart!, end: value.location)
                marqueeRect = rect
                let hit = cellFrames.filter { $0.value.intersects(rect) }.keys
                selectedIDs = marqueeBase.union(hit)
                anchorID = hit.first
            }
            .onEnded { _ in
                marqueeStart = nil
                marqueeRect = nil
                marqueeBase = []
                gridFocused = true
            }
    }

    // MARK: Click selection

    private func handleClick(_ asset: ImmichAsset) {
        gridFocused = true
        let mods = NSEvent.modifierFlags
        if mods.contains(.command) {
            toggle(asset.id)
            anchorID = asset.id
        } else if mods.contains(.shift), let anchor = anchorID {
            selectRange(from: anchor, to: asset.id)
        } else {
            selectedIDs = [asset.id]
            anchorID = asset.id
        }
    }

    private func toggle(_ id: String) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
    }

    private func selectRange(from anchor: String, to target: String) {
        let ids = assets.map(\.id)
        guard let a = ids.firstIndex(of: anchor), let b = ids.firstIndex(of: target) else { return }
        let range = a <= b ? a...b : b...a
        selectedIDs = Set(ids[range])
    }

    // MARK: Keyboard

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        if settings.matches(press, .selectAll) {
            selectedIDs = Set(assets.map(\.id))
            return .handled
        }
        if press.key == .escape {
            selectedIDs = []
            return .handled
        }
        if settings.matches(press, .trash) && !selectedIDs.isEmpty {
            confirmTrash = true
            return .handled
        }
        if settings.matches(press, .startCulling) {
            startCull()
            return .handled
        }
        switch press.key {
        case .leftArrow: moveCursor(by: -1, extend: press.modifiers.contains(.shift)); return .handled
        case .rightArrow: moveCursor(by: 1, extend: press.modifiers.contains(.shift)); return .handled
        case .upArrow: moveCursor(by: -columnCount, extend: press.modifiers.contains(.shift)); return .handled
        case .downArrow: moveCursor(by: columnCount, extend: press.modifiers.contains(.shift)); return .handled
        default: return .ignored
        }
    }

    private func moveCursor(by delta: Int, extend: Bool) {
        let ids = assets.map(\.id)
        guard !ids.isEmpty else { return }
        let currentIndex = anchorID.flatMap { ids.firstIndex(of: $0) } ?? 0
        let next = min(max(currentIndex + delta, 0), ids.count - 1)
        let nextID = ids[next]
        if extend, let anchor = selectionAnchor(in: ids) {
            let range = anchor <= next ? anchor...next : next...anchor
            selectedIDs = Set(ids[range])
        } else {
            selectedIDs = [nextID]
        }
        anchorID = nextID
    }

    private func selectionAnchor(in ids: [String]) -> Int? {
        anchorID.flatMap { ids.firstIndex(of: $0) }
    }

    // MARK: Bottom bar

    @ViewBuilder
    private var bottomBar: some View {
        if !selectedIDs.isEmpty {
            HStack {
                Text("\(selectedIDs.count) selected")
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    startCull()
                } label: {
                    Label("Cull from Selection", systemImage: "rectangle.portrait.on.rectangle.portrait.angled")
                }
                Button(role: .destructive) {
                    confirmTrash = true
                } label: {
                    Label("Move \(selectedIDs.count) to Trash", systemImage: "trash")
                }
                .keyboardShortcut(.delete, modifiers: [])
            }
            .padding(10)
            .background(.bar)
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text(selection.title).font(.headline)
        }
        ToolbarItemGroup {
            Picker("Media", selection: $filter) {
                ForEach(MediaTypeFilter.allCases) { option in
                    Label(option.label, systemImage: option.systemImage).tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            if !assets.isEmpty {
                Button(selectedIDs.count == assets.count ? "Deselect All" : "Select All") {
                    selectedIDs = selectedIDs.count == assets.count ? [] : Set(assets.map(\.id))
                }
            }

            Button {
                startCull(forceFirst: true)
            } label: {
                Label("Start Culling", systemImage: "play.fill")
            }
            .disabled(assets.isEmpty)
        }
    }

    private var trashPrompt: String {
        selectedIDs.count == 1 ? "Move 1 asset to the Immich trash?"
                               : "Move \(selectedIDs.count) assets to the Immich trash?"
    }

    // MARK: Actions

    private func startCull(forceFirst: Bool = false) {
        guard !assets.isEmpty else { return }
        if forceFirst { onStartCull(nil); return }
        // Start at the (first) selected asset if any, else the beginning.
        let ordered = assets.map(\.id)
        let start = ordered.first { selectedIDs.contains($0) }
        onStartCull(start)
    }

    private func trashSelected() {
        let targets = assets.filter { selectedIDs.contains($0.id) }
        guard !targets.isEmpty, let client = settings.client else { return }
        let ids = Set(targets.map(\.id))
        let serverIDs = targets.idsIncludingLivePhotoPairs
        allAssets.removeAll { ids.contains($0.id) }
        selectedIDs = []
        stats.recordTrashed(count: targets.count)
        if assets.isEmpty { phase = .empty }
        Task {
            do {
                try await client.trashAssets(ids: serverIDs)
                onTrashed()
            } catch {
                trashError = error.localizedDescription
            }
        }
    }

    // MARK: Loading

    private func load() async {
        guard let client = settings.client else { phase = .failed("Not connected."); return }
        phase = .loading
        selectedIDs = []
        anchorID = nil
        if !didSetInitialFilter {
            filter = settings.mediaFilter
            didSetInitialFilter = true
        }
        do {
            let fetched = try await client.fetchAssets(
                albumIDs: selection.albumIDs, tagIDs: nil, order: settings.order.apiValue,
                limit: 5000, isNotInAlbum: selection.isNotInAlbum ? true : nil, visibility: "timeline")
            allAssets = fetched.filter { $0.type == .image || $0.type == .video }
            phase = allAssets.isEmpty ? .empty : .loaded
            await seedStates(client: client)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func seedStates(client: ImmichClient) async {
        let checkedIDs = (try? await client.assetIDs(
            withAnyTagNamed: settings.checkedTagNames + [settings.markTagName])) ?? []
        states = allAssets.reduce(into: [:]) { result, asset in
            result[asset.id] = AssetCullState(
                isFavorite: asset.isFavorite ?? false,
                isInDestinationAlbum: false,
                isChecked: checkedIDs.contains(asset.id))
        }
    }
}

/// Publishes each visible cell's frame in the "grid" coordinate space.
private struct CellFrameKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private extension CGRect {
    init(start: CGPoint, end: CGPoint) {
        self.init(x: min(start.x, end.x), y: min(start.y, end.y),
                  width: abs(start.x - end.x), height: abs(start.y - end.y))
    }
}
