import CoreGraphics

/// Where the launcher panel goes on a screen.
public enum PanelFrame {
    /// The gap kept between the panel and the visible frame's edges.
    public static let margin: CGFloat = 24

    /// The panel's origin in `visible` (a screen's visibleFrame, so the menu bar
    /// and Dock are already left out): centred horizontally, a sixth of the
    /// height above the middle, but never past the top or bottom margin. On a
    /// screen too short for the panel, its top edge (the search field) stays visible.
    public static func origin(size: CGSize, in visible: CGRect) -> CGPoint {
        let preferred = visible.midY - size.height / 2 + visible.height / 6
        var y = min(visible.maxY - size.height - margin, preferred)
        y = max(y, visible.minY + margin)
        if y + size.height > visible.maxY { y = visible.maxY - size.height }
        let x = max(visible.minX, min(visible.midX - size.width / 2, visible.maxX - size.width))
        return CGPoint(x: x, y: y)
    }
}
