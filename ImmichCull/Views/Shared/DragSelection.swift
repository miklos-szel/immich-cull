import SwiftUI

/// Photos-app style "paint" selection: press and hold a cell, then slide the
/// finger across the grid to select (or deselect) everything it passes over.
///
/// Cells publish their frames through a preference; the container hit-tests the
/// drag location against them. Attaching the gesture with `simultaneousGesture`
/// is what keeps the existing interactions alive — a plain swipe still scrolls,
/// and a plain tap still activates the cell's own button.
enum DragSelection {
    static let coordinateSpace = "dragSelection"
    /// Long enough not to fire while flicking through the grid, short enough
    /// that it doesn't feel like a stall.
    static let pressDuration = 0.3
}

/// Frames of the currently laid-out cells, keyed by selection ID. `LazyVGrid`
/// only builds visible cells, so this holds the on-screen ones — which is all a
/// paint gesture can reach anyway.
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
    }

    /// Enables paint selection over the cells inside this container.
    ///
    /// - Parameters:
    ///   - isEnabled: `false` leaves the container's gestures untouched.
    ///   - isSelected: current state of a cell, used to decide whether the
    ///     gesture selects or deselects.
    ///   - onPaint: called once per cell the finger enters, with the state that
    ///     cell should take.
    func dragSelection(
        isEnabled: Bool = true,
        isSelected: @escaping (String) -> Bool,
        onPaint: @escaping (String, Bool) -> Void
    ) -> some View {
        modifier(DragSelectionModifier(isEnabled: isEnabled, isSelected: isSelected, onPaint: onPaint))
    }
}

private struct DragSelectionModifier: ViewModifier {
    let isEnabled: Bool
    let isSelected: (String) -> Bool
    let onPaint: (String, Bool) -> Void

    @State private var frames: [String: CGRect] = [:]
    /// Whether this drag is selecting or deselecting — decided by the cell the
    /// press landed on, then applied to every cell after it.
    @State private var paintMode: Bool?
    /// Stops the value flapping while the finger jitters inside one cell.
    @State private var lastPaintedID: String?
    @State private var feedback = 0

    func body(content: Content) -> some View {
        content
            .coordinateSpace(name: DragSelection.coordinateSpace)
            .onPreferenceChange(DragSelectionFrameKey.self) { frames = $0 }
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
                // `.second(_, nil)` is the press landing before the drag has
                // reported a location yet; there's nothing to hit-test.
                if case .second(_, let drag?) = value {
                    paint(at: drag.location)
                }
            }
            .onEnded { value in
                // Covers a press-and-lift with no movement at all.
                if case .second(_, let drag?) = value {
                    paint(at: drag.location)
                }
                paintMode = nil
                lastPaintedID = nil
            }
    }

    private func paint(at location: CGPoint) {
        guard let id = frames.first(where: { $0.value.contains(location) })?.key,
              id != lastPaintedID else { return }
        // The cell under the press decides the direction: land on an unselected
        // photo and you paint selection, land on a selected one and you erase it.
        let mode = paintMode ?? !isSelected(id)
        paintMode = mode
        lastPaintedID = id
        feedback += 1
        onPaint(id, mode)
    }
}
