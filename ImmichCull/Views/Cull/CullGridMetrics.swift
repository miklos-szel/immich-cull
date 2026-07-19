import SwiftUI

/// Works out how many square cells fit on one page of the culling grid.
///
/// The grid is paged rather than scrolled so that selection drags never
/// compete with a scroll view for the touch — which means the page has to size
/// itself to the space available instead of running off the bottom.
enum CullGridMetrics {
    static let spacing: CGFloat = 4
    static let columns = 3

    /// Whole rows that fit in `size`, at least one even on a tiny screen.
    static func rows(fitting size: CGSize) -> Int {
        let cellSide = cellSide(forWidth: size.width)
        guard cellSide > 0 else { return 1 }
        let available = size.height + spacing
        return max(1, Int(available / (cellSide + spacing)))
    }

    static func pageSize(fitting size: CGSize) -> Int {
        rows(fitting: size) * columns
    }

    private static func cellSide(forWidth width: CGFloat) -> CGFloat {
        let gutters = spacing * CGFloat(columns + 1)
        return (width - gutters) / CGFloat(columns)
    }
}
