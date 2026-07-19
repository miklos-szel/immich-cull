import SwiftUI
import UIKit

/// Turns the enclosing scroll view's pan on and off.
///
/// The only `UIViewRepresentable` in the app, and it exists for one reason:
/// `.scrollDisabled` cannot stop a drag that is already under way, because UIKit
/// keeps delivering a pan it has started tracking regardless of
/// `isScrollEnabled`. Disabling the recognizer itself *does* cancel it, and
/// SwiftUI offers no way to reach it — hence reaching through to UIKit.
///
/// `DragSelection` needs this so the grid stays put under a paint drag.
/// Programmatic scrolling (`ScrollViewProxy.scrollTo`) is unaffected, so
/// edge auto-scroll keeps working while the pan is off.
struct ScrollPanDisabler: UIViewRepresentable {
    /// `true` while painting: the finger must move the selection, not the grid.
    let isPaused: Bool

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        // Purely a probe — it must never intercept a touch itself.
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        let scrollView = context.coordinator.scrollView(from: view)
        scrollView?.panGestureRecognizer.isEnabled = !isPaused
    }

    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
        // A gesture cancelled mid-paint must not strand an unscrollable grid.
        coordinator.cached?.panGestureRecognizer.isEnabled = true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        /// Held weakly and looked up once: the hierarchy walk is cheap but runs
        /// on every state change while a drag is in flight.
        weak var cached: UIScrollView?

        func scrollView(from view: UIView) -> UIScrollView? {
            if let cached { return cached }
            let found = Self.findScrollView(from: view)
            cached = found
            return found
        }

        /// The probe lives in the modifier's `.background`, which SwiftUI places
        /// as a sibling of the scroll view rather than inside it — so walking up
        /// alone never reaches it. Each ancestor is therefore also searched
        /// downwards, nearest first.
        private static func findScrollView(from view: UIView) -> UIScrollView? {
            var ancestor: UIView? = view
            while let current = ancestor {
                if let scrollView = current as? UIScrollView { return scrollView }
                if let descendant = firstScrollView(in: current) { return descendant }
                ancestor = current.superview
            }
            return nil
        }

        private static func firstScrollView(in root: UIView) -> UIScrollView? {
            var queue = root.subviews
            var index = 0
            while index < queue.count {
                let candidate = queue[index]
                index += 1
                if let scrollView = candidate as? UIScrollView { return scrollView }
                queue.append(contentsOf: candidate.subviews)
            }
            return nil
        }
    }
}
