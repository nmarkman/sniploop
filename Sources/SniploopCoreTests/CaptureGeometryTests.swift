import CoreGraphics
import SniploopCore

func runCaptureGeometryTests() {
    // AppKit selection is bottom-left origin; SCK sourceRect is top-left origin, in points.
    T.eq(CaptureGeometry.sourceRectTopLeft(selection: CGRect(x: 100, y: 300, width: 100, height: 100),
                                           displayHeightPoints: 1000),
         CGRect(x: 100, y: 600, width: 100, height: 100), "sourceRect flips Y to top-left")

    let s = CaptureGeometry.outputPixelSize(selection: CGRect(x: 0, y: 0, width: 640, height: 360), scale: 2)
    T.eq(s.width, 1280, "output width applies scale")
    T.eq(s.height, 720, "output height applies scale")

    let r = CaptureGeometry.outputPixelSize(selection: CGRect(x: 0, y: 0, width: 100.4, height: 100.6), scale: 1)
    T.eq(r.width, 100, "rounds width to nearest pixel")
    T.eq(r.height, 101, "rounds height to nearest pixel")
}
