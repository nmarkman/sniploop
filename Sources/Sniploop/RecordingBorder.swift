import AppKit

/// A thin frame drawn just OUTSIDE a screen region, click-through, that persists while recording.
/// The captured area is exactly the inner region, so the stroke (which lives in the outer ring)
/// is never part of the output.
final class RecordingBorder {
    private let window: NSWindow
    private static let thickness: CGFloat = 3

    /// `region` is the captured area in global screen points (bottom-left origin).
    init(around region: NSRect) {
        let t = RecordingBorder.thickness
        let frame = region.insetBy(dx: -t, dy: -t) // extend t points beyond the region on every side
        window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true // click-through; the user keeps interacting with the recorded app
        window.hasShadow = false
        window.contentView = BorderView(frame: NSRect(origin: .zero, size: frame.size), thickness: t)
    }

    func show() { window.orderFrontRegardless() }
    func close() { window.orderOut(nil) }
}

private final class BorderView: NSView {
    private let thickness: CGFloat

    init(frame: NSRect, thickness: CGFloat) {
        self.thickness = thickness
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        // The stroke occupies the outer ring (window edge inward by `thickness`), i.e. just outside
        // the captured region, so it never lands in the recording. The inner area stays transparent.
        NSColor.systemRed.setStroke()
        let path = NSBezierPath(rect: bounds.insetBy(dx: thickness / 2, dy: thickness / 2))
        path.lineWidth = thickness
        path.stroke()
    }
}
