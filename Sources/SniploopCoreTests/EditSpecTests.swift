import CoreGraphics
import SniploopCore

func runEditSpecTests() {
    let s = EditSpec.identity(duration: 5.0, fps: 15)
    T.eq(s.startSeconds, 0.0, "identity start")
    T.eq(s.endSeconds, 5.0, "identity end")
    T.ok(s.cropPixels == nil, "identity no crop")
    T.ok(s.maxWidth == nil, "identity no maxWidth")
    T.eq(s.fps, 15, "identity fps")
    T.ok(s.isTrimOnly, "identity is trim-only")
    T.close(s.durationSeconds, 5.0, 1e-9, "identity duration")

    var cropped = EditSpec.identity(duration: 5, fps: 15)
    cropped.cropPixels = CGRect(x: 0, y: 0, width: 10, height: 10)
    T.ok(!cropped.isTrimOnly, "cropped is not trim-only")

    let o1 = EditSpec.identity(duration: 5, fps: 15).outputSize(sourceWidth: 1280, sourceHeight: 720)
    T.eq(o1.width, 1280, "no maxWidth keeps source width")
    T.eq(o1.height, 720, "no maxWidth keeps source height")

    var scaled = EditSpec.identity(duration: 5, fps: 15); scaled.maxWidth = 640
    let o2 = scaled.outputSize(sourceWidth: 1280, sourceHeight: 720)
    T.eq(o2.width, 640, "scales width to maxWidth")
    T.eq(o2.height, 360, "scales height preserving aspect")

    var big = EditSpec.identity(duration: 5, fps: 15); big.maxWidth = 2000
    let o3 = big.outputSize(sourceWidth: 1280, sourceHeight: 720)
    T.eq(o3.width, 1280, "does not upscale width")
    T.eq(o3.height, 720, "does not upscale height")

    var cropScaled = EditSpec.identity(duration: 5, fps: 15)
    cropScaled.cropPixels = CGRect(x: 0, y: 0, width: 800, height: 400)
    cropScaled.maxWidth = 400
    let o4 = cropScaled.outputSize(sourceWidth: 1280, sourceHeight: 720)
    T.eq(o4.width, 400, "uses crop as base width")
    T.eq(o4.height, 200, "uses crop as base height")
}
