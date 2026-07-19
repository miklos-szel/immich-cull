import SwiftUI

/// The swipeable card deck plus footer controls. Swipe directions map to
/// actions via Settings (defaults: up = trash, left = next image, down = add
/// to album, right = previous image).
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
    /// Action being committed. While set, the drag state is frozen: the release
    /// animation drives `dragOffset` sideways, and recomputing from it would
    /// flip the trash marker to a different action mid-flight.
    @State private var committingAction: SwipeAction?

    private static let threshold = 80.0
    /// Thin divider between pages while swiping, so the neighbouring image
    /// sits right alongside rather than a wide gutter away.
    private static let pageGap = 4.0
    /// Resistance applied when dragging toward a page that doesn't exist.
    private static let edgeResistance = 0.35

    var body: some View {
        VStack(spacing: 0) {
            deck
            footer
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: session.reviewedCount)
    }

    private var deck: some View {
        GeometryReader { proxy in
            let page = proxy.size.width + Self.pageGap
            ZStack {
                // Keyed by asset ID so a card keeps its identity — and its
                // already-loaded image — when the queue advances underneath it.
                // Rebuilding it here is what made the photo flicker.
                ForEach(deckCards) { card in
                    AssetCardView(
                        asset: card.asset,
                        client: client,
                        isTopCard: card.slot == 0,
                        // Skip past assets the server can't serve at all rather
                        // than parking a dead card in front of the user.
                        onUnavailable: { session.dropUnavailable(card.asset) }
                    )
                    .offset(x: offsetX(for: card.slot, page: page),
                            y: card.slot == 0 ? verticalOffset : 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) {
                TrashMarkerView(progress: trashProgress)
                    .padding(.top, 16)
            }
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

    // MARK: Deck contents

    /// One card per visible page: -1 previous, 0 current, +1 next.
    private struct DeckCard: Identifiable {
        let asset: ImmichAsset
        let slot: Int
        var id: String { asset.id }
    }

    private var deckCards: [DeckCard] {
        var cards: [DeckCard] = []
        var seen: Set<String> = []
        if let previous = session.previousAsset, seen.insert(previous.id).inserted {
            cards.append(DeckCard(asset: previous, slot: -1))
        }
        if let current = session.current, seen.insert(current.id).inserted {
            cards.append(DeckCard(asset: current, slot: 0))
        }
        if let next = session.upNext, seen.insert(next.id).inserted {
            cards.append(DeckCard(asset: next, slot: 1))
        }
        return cards
    }

    private func offsetX(for slot: Int, page: Double) -> Double {
        Double(slot) * page + pagedOffset
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
        // Frozen while committing; see `committingAction`.
        guard committingAction == nil else { return nil }
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

    /// Trashing is the only destructive action, so it's the only one marked.
    private var trashProgress: Double {
        if committingAction == .trash { return 1 }
        guard pendingAction == .trash else { return 0 }
        return dragProgress
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
        committingAction = action
        // Slide the neighbouring page exactly into the centre, then swap the
        // queue underneath it so the handoff is invisible.
        withAnimation(.snappy(duration: 0.28)) {
            dragOffset = CGSize(width: backward ? page : -page, height: 0)
        } completion: {
            perform(action)
            dragOffset = .zero
            committingAction = nil
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
