import SwiftUI
import UIKit

/// Photos-app style "paint" selection: press and hold a cell, then slide the
/// finger to extend the selection to everything between that cell and the one
/// under the finger — so dragging onto a second row takes the rest of the first
/// row with it. Dragging back up again releases what it passes.
///
/// Cells publish their frames through a preference; the container hit-tests the
/// drag location against them and works in **index ranges**, not individual
/// cells, so a fast drag can't skip anything it flew over.
enum DragSelection {
    static let coordinateSpace = "dragSelection"
    /// Long enough not to fire while flicking through the grid, short enough
    /// that it doesn't feel like a stall.
    static let pressDuration = 0.3
}

/// Frames of the currently laid-out cells, keyed by selection ID. `LazyVGrid`
/// only builds visible cells, so this holds the on-screen ones.
struct DragSelectionFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] { [:] }

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Registers this cell's frame so a drag can find it by location.
    func dragSelectCell(id: String) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: DragSelectionFrameKey.self,
                    value: [id: proxy.frame(in: .named(DragSelection.coordinateSpace))]
                )
            }
        }
        .id(id)
    }

    /// Enables paint selection over the cells inside this scrollable container.
    ///
    /// - Parameters:
    ///   - ids: every cell's ID **in display order** — the order the range is
    ///     filled in. Only the on-screen ones need to be laid out.
    ///   - isEnabled: `false` leaves the container's gestures untouched.
    ///   - isSelected: current state of a cell, used to decide whether the
    ///     gesture selects or deselects.
    ///   - onPaint: called for each cell entering or leaving the dragged range,
    ///     with the state that cell should take.
    ///   - autoScroll: when `true`, holding the finger against the top or bottom
    ///     edge scrolls the container and keeps painting the rows that come into
    ///     view — the Photos behaviour. Off by default so the paged grids, which
    ///     have nothing to scroll, are untouched.
    func dragSelection(
        ids: [String],
        isEnabled: Bool = true,
        autoScroll: Bool = false,
        isSelected: @escaping (String) -> Bool,
        onPaint: @escaping (String, Bool) -> Void
    ) -> some View {
        modifier(DragSelectionModifier(
            ids: ids,
            isEnabled: isEnabled,
            autoScroll: autoScroll,
            isSelected: isSelected,
            onPaint: onPaint
        ))
    }
}

/// Height of the scrollable container, so the modifier knows where its top and
/// bottom edges are for the auto-scroll bands.
private struct DragContainerHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Drives edge auto-scroll off a display link. Not actor-isolated on purpose:
/// `CADisplayLink` fires on the main run loop, so every access here is already
/// on the main thread, and staying a plain `NSObject` avoids `@objc`/isolation
/// friction on the selector.
final class DragAutoScroller: NSObject {
    weak var scrollView: UIScrollView?
    /// Called after each scroll step so the caller can re-paint at the last
    /// finger location against the rows that just came into view.
    var onScroll: (() -> Void)?

    /// Points per frame; positive scrolls down, negative up, zero stops.
    private var velocity: CGFloat = 0
    private var link: CADisplayLink?

    func setVelocity(_ newValue: CGFloat) {
        velocity = newValue
        if newValue == 0 {
            stop()
        } else if link == nil {
            let link = CADisplayLink(target: self, selector: #selector(step))
            link.add(to: .main, forMode: .common)
            self.link = link
        }
    }

    func stop() {
        velocity = 0
        link?.invalidate()
        link = nil
    }

    @objc private func step() {
        guard let scrollView, velocity != 0 else { return }
        let minY = -scrollView.adjustedContentInset.top
        let maxY = max(minY, scrollView.contentSize.height - scrollView.bounds.height
                       + scrollView.adjustedContentInset.bottom)
        let target = min(max(minY, scrollView.contentOffset.y + velocity), maxY)
        guard target != scrollView.contentOffset.y else { return }
        scrollView.contentOffset.y = target
        onScroll?()
    }
}

private struct DragSelectionModifier: ViewModifier {
    let ids: [String]
    let isEnabled: Bool
    let autoScroll: Bool
    let isSelected: (String) -> Bool
    let onPaint: (String, Bool) -> Void

    /// Distance from an edge at which auto-scroll kicks in, and the top speed
    /// (points per frame) reached at the very edge.
    private static let edgeBand: CGFloat = 90
    private static let maxSpeed: CGFloat = 14

    @State private var frames: [String: CGRect] = [:]
    @State private var containerHeight: CGFloat = 0
    /// Last finger location, in the container's coordinate space, so a display
    /// link tick can re-paint there while the finger holds still at an edge.
    @State private var lastLocation: CGPoint = .zero
    @State private var scroller = DragAutoScroller()
    /// Whether this drag is selecting or deselecting — decided by the cell the
    /// press landed on, then applied to the whole range behind it.
    @State private var paintMode: Bool?
    /// Where the drag started, in `ids` order. The range always runs from here.
    @State private var anchorIndex: Int?
    /// What the range covered last time, so shrinking the drag can undo the
    /// part that's no longer covered.
    @State private var paintedRange: ClosedRange<Int>?
    @State private var feedback = 0
    /// Set the moment the press is recognised, while the finger is still
    /// stationary, so the container stops panning before the drag begins.
    @State private var isPainting = false

    func body(content: Content) -> some View {
        content
            // No `scrollDisabled` here on purpose: UIKit ignores a scroll
            // view being disabled mid-touch once its pan is already
            // tracking, so the lock never worked. The gesture below keeps
            // the touch away from the scroll view instead.
            .coordinateSpace(name: DragSelection.coordinateSpace)
            // Pins the grid for the duration of a paint drag. This is what
            // `.scrollDisabled` could not do — see ScrollPanDisabler. When
            // auto-scroll is on, it also hands us the scroll view to drive.
            .background {
                ScrollPanDisabler(isPaused: isPainting) { scrollView in
                    if autoScroll { scroller.scrollView = scrollView }
                }
            }
            // The container's own size, for locating the auto-scroll edge bands.
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: DragContainerHeightKey.self, value: proxy.size.height)
                }
            }
            .onPreferenceChange(DragContainerHeightKey.self) { containerHeight = $0 }
            .onAppear {
                // Re-paint at the held location as new rows scroll under it.
                scroller.onScroll = { extendSelection(to: lastLocation) }
            }
            .onPreferenceChange(DragSelectionFrameKey.self) { frames = $0 }
            // Stays `simultaneousGesture` so taps still reach the cells' own
            // buttons; `highPriorityGesture` would pin the grid too, but it
            // swallows every tap. The pan recognizer above does the pinning.
            .simultaneousGesture(paintGesture, including: isEnabled ? .all : .subviews)
            .sensoryFeedback(.selection, trigger: feedback)
    }

    private var paintGesture: some Gesture {
        LongPressGesture(minimumDuration: DragSelection.pressDuration)
            .sequenced(before: DragGesture(
                minimumDistance: 0,
                coordinateSpace: .named(DragSelection.coordinateSpace)
            ))
            .onChanged { value in
                // `.second` means the press was held long enough. Lock scrolling
                // here, while the finger is still stationary — the drag hasn't
                // reported a location yet (`nil`), so there's nothing to paint.
                guard case .second(_, let drag) = value else { return }
                isPainting = true
                if let drag {
                    lastLocation = drag.location
                    extendSelection(to: drag.location)
                    updateAutoScroll(for: drag.location)
                }
            }
            .onEnded { value in
                // Covers a press-and-lift with no movement at all.
                if case .second(_, let drag?) = value {
                    extendSelection(to: drag.location)
                }
                scroller.stop()
                isPainting = false
                paintMode = nil
                anchorIndex = nil
                paintedRange = nil
            }
    }

    // MARK: - Painting

    private func extendSelection(to location: CGPoint) {
        guard let index = index(at: location) else { return }

        guard let anchorIndex, let paintMode else {
            // First cell decides the direction: land on an unselected photo and
            // the drag selects, land on a selected one and it clears.
            let mode = !isSelected(ids[index])
            self.anchorIndex = index
            self.paintMode = mode
            apply(mode, to: index...index)
            paintedRange = index...index
            feedback += 1
            return
        }

        let range = min(anchorIndex, index)...max(anchorIndex, index)
        guard range != paintedRange else { return }

        // Anything the drag no longer covers goes back to how it started.
        if let paintedRange {
            for i in paintedRange where !range.contains(i) {
                onPaint(ids[i], !paintMode)
            }
        }
        // The whole range every time, not just the newly-entered part: painting
        // is idempotent, and re-applying it means a cell that was missed once
        // can't stay missed for the rest of the drag.
        apply(paintMode, to: range)
        paintedRange = range
        feedback += 1
    }

    private func apply(_ mode: Bool, to range: ClosedRange<Int>) {
        for i in range {
            onPaint(ids[i], mode)
        }
    }

    /// Sets the auto-scroll speed from how deep the finger is into the top or
    /// bottom edge band. Zero (and stop) anywhere in the middle.
    private func updateAutoScroll(for location: CGPoint) {
        guard autoScroll, containerHeight > 0 else { return }
        let band = Self.edgeBand
        let velocity: CGFloat
        if location.y < band {
            // Deeper past the edge → faster; ramps 0…1 across the band.
            velocity = -Self.maxSpeed * min(1, (band - location.y) / band)
        } else if location.y > containerHeight - band {
            velocity = Self.maxSpeed * min(1, (location.y - (containerHeight - band)) / band)
        } else {
            velocity = 0
        }
        scroller.setVelocity(velocity)
    }

    /// Nearest cell centre rather than `contains`. A point in the gap between
    /// cells belongs to no frame at all, and a point on a shared edge belongs to
    /// two — and `Dictionary.first(where:)` would pick between them arbitrarily,
    /// which is how a press on the first cell could anchor on its neighbour.
    private func index(at location: CGPoint) -> Int? {
        var best: (index: Int, distance: CGFloat)?
        for (id, frame) in frames {
            guard let index = ids.firstIndex(of: id) else { continue }
            let dx = location.x - frame.midX
            let dy = location.y - frame.midY
            let distance = (dx * dx) + (dy * dy)
            if best == nil || distance < best!.distance {
                best = (index, distance)
            }
        }
        return best?.index
    }

}
