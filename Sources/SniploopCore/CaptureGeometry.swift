import CoreGraphics

public enum CaptureGeometry {
    /// Convert a selection rect in screen points (bottom-left origin, relative to the display's
    /// own frame) into a ScreenCaptureKit `sourceRect` in points with a top-left origin.
    public static func sourceRectTopLeft(selection: CGRect, displayHeightPoints: CGFloat) -> CGRect {
        CGRect(
            x: selection.minX,
            y: displayHeightPoints - selection.maxY,
            width: selection.width,
            height: selection.height
        )
    }

    /// The output frame size in pixels for the captured region at the given backing scale.
    public static func outputPixelSize(selection: CGRect, scale: CGFloat) -> (width: Int, height: Int) {
        (
            width: Int((selection.width * scale).rounded()),
            height: Int((selection.height * scale).rounded())
        )
    }
}
