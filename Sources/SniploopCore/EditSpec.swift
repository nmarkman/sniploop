import CoreGraphics

public struct EditSpec: Equatable {
    /// Trim window, in seconds, within the master clip.
    public var startSeconds: Double
    public var endSeconds: Double
    /// Crop rectangle in pixels (top-left origin) within the master frame; nil means no crop.
    public var cropPixels: CGRect?
    /// Maximum output width in pixels; nil means keep the base width.
    public var maxWidth: Int?
    /// Output frames per second.
    public var fps: Int

    public init(startSeconds: Double, endSeconds: Double, cropPixels: CGRect? = nil, maxWidth: Int? = nil, fps: Int) {
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.cropPixels = cropPixels
        self.maxWidth = maxWidth
        self.fps = fps
    }

    public static func identity(duration: Double, fps: Int) -> EditSpec {
        EditSpec(startSeconds: 0, endSeconds: duration, cropPixels: nil, maxWidth: nil, fps: fps)
    }

    public var durationSeconds: Double { max(0, endSeconds - startSeconds) }

    public var isTrimOnly: Bool { cropPixels == nil && maxWidth == nil }

    /// Output pixel size after applying crop (if any) then max-width downscale (aspect preserved, no upscale).
    public func outputSize(sourceWidth: Int, sourceHeight: Int) -> (width: Int, height: Int) {
        let baseW = cropPixels.map { Int($0.width) } ?? sourceWidth
        let baseH = cropPixels.map { Int($0.height) } ?? sourceHeight
        guard let maxW = maxWidth, maxW < baseW, baseW > 0 else {
            return (baseW, baseH)
        }
        let ratio = Double(maxW) / Double(baseW)
        return (maxW, max(1, Int((Double(baseH) * ratio).rounded())))
    }
}
