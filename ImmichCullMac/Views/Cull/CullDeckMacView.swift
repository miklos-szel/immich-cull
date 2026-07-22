import SwiftUI

/// The single-card culling view. Keyboard-first: every action has a configurable
/// shortcut handled here; the footer buttons are the mouse fallback and display
/// each shortcut. Action dispatch mirrors the iOS deck.
struct CullDeckMacView: View {
    let session: CullSession

    @Environment(SettingsStore.self) private var settings
    @FocusState private var focused: Bool
    @State private var showOverview = false

    var body: some View {
        VStack(spacing: 0) {
            if let message = session.errorMessage {
                banner(message)
            }
            card
            Divider()
            footer
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(phases: .down) { handleKey($0) }
        .sheet(isPresented: $showOverview) {
            CullOverviewMacView(session: session) { showOverview = false }
                .frame(minWidth: 700, minHeight: 520)
        }
    }

    // MARK: Card

    @ViewBuilder
    private var card: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            if let current = session.current, let client = settings.client {
                if current.type == .video {
                    VideoCardMacView(url: client.videoPlaybackURL(assetID: current.id), apiKey: settings.apiKey)
                        .padding(16)
                } else {
                    RemoteImageMacView(
                        url: client.thumbnailURL(assetID: current.id),
                        apiKey: settings.apiKey,
                        contentMode: .fit,
                        fallbackURL: client.originalURL(assetID: current.id),
                        onUnavailable: {
                            Task { await session.verifyAndDropIfMissing(current) }
                        })
                    .id(current.id)
                    .padding(16)
                    .overlay(alignment: .top) { stateBadges(for: current) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func stateBadges(for asset: ImmichAsset) -> some View {
        let state = session.state(for: asset)
        if !state.isEmpty {
            AssetStateBadgesView(state: state).padding(.top, 8)
        }
    }

    private func banner(_ message: String) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.white)
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(.red)
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 8) {
            if settings.showCardInfo, let current = session.current {
                VStack(spacing: 1) {
                    Text(current.originalFileName).font(.subheadline)
                    if let date = current.takenAt {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 12) {
                ForEach(MacAction.deckActions) { action in
                    actionButton(action)
                }
            }

            HStack {
                mediaFilterMenu
                Spacer()
                Text("\(min(session.reviewedCount + 1, session.totalCount)) of \(session.totalCount)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showOverview = true
                } label: {
                    Label("Grid", systemImage: "square.grid.2x2")
                }
            }
        }
        .padding(12)
    }

    private func actionButton(_ action: MacAction) -> some View {
        Button {
            dispatch(action)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: action.systemImage)
                    .font(.title3)
                Text(settings.shortcut(for: action).displayString)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 76)
            .contentShape(.rect)
        }
        .buttonStyle(.bordered)
        .tint(action.tint)
        .disabled(!isEnabled(action))
        .help(action.label)
    }

    private var mediaFilterMenu: some View {
        Menu {
            ForEach(MediaTypeFilter.allCases) { option in
                Button {
                    session.setMediaFilter(option)
                } label: {
                    if session.mediaFilter == option {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
        } label: {
            Label(session.mediaFilter.label, systemImage: session.mediaFilter.systemImage)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: Dispatch

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        for action in MacAction.deckActions where settings.matches(press, action) {
            guard isEnabled(action) else { return .handled }
            dispatch(action)
            return .handled
        }
        return .ignored
    }

    private func isEnabled(_ action: MacAction) -> Bool {
        switch action {
        case .undo: session.canUndo
        case .previousImage: session.canGoToPreviousImage
        case .saveToAlbum: session.hasDestinationAlbum && session.current != nil
        case .trash, .nextImage, .favorite: session.current != nil
        default: true
        }
    }

    private func dispatch(_ action: MacAction) {
        switch action {
        case .trash: session.trashCurrent()
        case .nextImage: session.skipCurrent()
        case .saveToAlbum: session.saveCurrentToAlbum()
        case .favorite: session.favoriteCurrent()
        case .previousImage: session.goToPreviousImage()
        case .undo: session.undo()
        default: break
        }
    }
}
