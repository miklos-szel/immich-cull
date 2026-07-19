import SwiftUI

/// The swipeable card deck plus footer controls. Swipe directions map to
/// actions via Settings (defaults: up = trash, left = next image, down = album,
/// right = undo).
///
/// The deck is a horizontal pager: the previous and next images sit one page to
/// either side and track the finger 1:1, so committing an action slides the
/// neighbour exactly into place before the queue advances — no visual jump.
struct CullDeckView: View {
    let session: CullSession
    let client: ImmichClient

    @Environment(SettingsStore.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGSize = .zero
    /// Keeps the banner's colour/label stable while it fades back out.
    @State private var lastPendingAction: SwipeAction = .nextImage

    private static let threshold = 80.0
    private static let pageGap = 16.0
    /// Resistance applied when dragging toward a page that doesn't exist.
    private static let edgeResistance = 0.35

    var body: some View {
        VStack(spacing: 0) {
            SwipeActionLineView(action: pendingAction ?? lastPendingAction,
                                progress: pendingAction == nil ? 0 : dragProgress)
                .padding(.horizontal)
                .padding(.top, 8)
            deck
            footer
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: session.reviewedCount)
        .onChange(of: pendingAction) {
            if let pendingAction {
                lastPendingAction = pendingAction
            }
        }
    }

    private var deck: some View {
        GeometryReader { proxy in
            let page = proxy.size.width + Self.pageGap
            let x = pagedOffset
            ZStack {
                if let previous = session.previousAsset {
                    AssetCardView(asset: previous, client: client, isTopCard: false)
                        .offset(x: -page + x)
                }
                if let next = session.upNext {
                    AssetCardView(asset: next, client: client, isTopCard: false)
                        .offset(x: page + x)
                }
                if let current = session.current {
                    AssetCardView(asset: current, client: client, isTopCard: true)
                        .id(current.id)
                        .offset(x: x, y: verticalOffset)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(dragGesture(page: page))
        }
        .clipped()
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var footer: some View {
        VStack(spacing: 6) {
            if settings.showCardInfo, let current = session.current {
                CardCaptionView(asset: current)
            }
            SessionStatsView(session: session)
            HStack {
                Button("Undo", systemImage: "arrow.uturn.backward", action: session.undo)
                    .disabled(!session.canUndo)
                Spacer()
                Text("\(session.reviewedCount + 1) of \(session.totalCount)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                GestureLegendView()
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
    }

    // MARK: Drag state

    /// Horizontal offset with rubber-banding when there is no page to reveal.
    private var pagedOffset: Double {
        let x = dragOffset.width
        if x < 0 && session.upNext == nil { return x * Self.edgeResistance }
        if x > 0 && session.previousAsset == nil { return x * Self.edgeResistance }
        return x
    }

    /// Vertical drags lift the current card only; horizontal drags page.
    private var verticalOffset: Double {
        abs(dragOffset.height) > abs(dragOffset.width) ? dragOffset.height : 0
    }

    private var activeDirection: SwipeDirection? {
        guard max(abs(dragOffset.width), abs(dragOffset.height)) > 12 else { return nil }
        if abs(dragOffset.height) > abs(dragOffset.width) {
            return dragOffset.height < 0 ? .up : .down
        }
        return dragOffset.width < 0 ? .left : .right
    }

    /// Action the current drag would trigger, nil when it would do nothing.
    private var pendingAction: SwipeAction? {
        guard let activeDirection else { return nil }
        let action = settings.action(for: activeDirection)
        switch action {
        case .disabled: return nil
        case .undo, .previousImage: return session.canUndo ? action : nil
        default: return action
        }
    }

    private var dragProgress: Double {
        min(max(abs(dragOffset.width), abs(dragOffset.height)) / Self.threshold, 1)
    }

    private func dragGesture(page: Double) -> some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
                handleDragEnd(value.translation, page: page)
            }
    }

    // MARK: Actions

    private func handleDragEnd(_ translation: CGSize, page: Double) {
        guard let direction = Self.direction(of: translation) else {
            snapBack()
            return
        }
        let action = settings.action(for: direction)
        guard action != .disabled else {
            snapBack()
            return
        }
        // Undo / previous page backward; everything else advances forward.
        let backward = (action == .undo || action == .previousImage)
        if backward && !session.canUndo {
            snapBack()
            return
        }

        guard !reduceMotion else {
            dragOffset = .zero
            perform(action)
            return
        }
        // Slide the neighbouring page exactly into the centre, then swap the
        // queue underneath it so the handoff is invisible.
        withAnimation(.snappy(duration: 0.28)) {
            dragOffset = CGSize(width: backward ? page : -page, height: 0)
        } completion: {
            perform(action)
            dragOffset = .zero
        }
    }

    private func perform(_ action: SwipeAction) {
        switch action {
        case .trash: session.trashCurrent()
        case .nextImage: session.skipCurrent()
        case .saveToAlbum: session.saveCurrentToAlbum()
        case .favorite: session.favoriteCurrent()
        case .previousImage: session.goToPreviousImage()
        case .undo: session.undo()
        case .disabled: break
        }
    }

    private static func direction(of translation: CGSize) -> SwipeDirection? {
        if abs(translation.height) > abs(translation.width) {
            if translation.height < -threshold { return .up }
            if translation.height > threshold { return .down }
        } else {
            if translation.width < -threshold { return .left }
            if translation.width > threshold { return .right }
        }
        return nil
    }

    private func snapBack() {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
            dragOffset = .zero
        }
    }
}
