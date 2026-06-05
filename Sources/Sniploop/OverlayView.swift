import AppKit
import SniploopCore

final class OverlayView: NSView {
    /// Called with the selected rect (view/screen points, bottom-left) when recording should start.
    var onRecord: ((NSRect) -> Void)?
    var onCancel: (() -> Void)?

    private var machine = SelectionMachine()
    private var dragOrigin: NSPoint?
    private var currentRect: NSRect?

    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        dragOrigin = p
        currentRect = NSRect(origin: p, size: .zero)
        machine.handle(.dragBegan(p))
        needsDisplay = true
    }

    override func mouseDragged(with e: NSEvent) {
        guard let o = dragOrigin else { return }
        let p = convert(e.locationInWindow, from: nil)
        let r = NSRect(x: min(o.x, p.x), y: min(o.y, p.y), width: abs(p.x - o.x), height: abs(p.y - o.y))
        currentRect = r
        machine.handle(.dragChanged(r))
        needsDisplay = true
    }

    override func mouseUp(with e: NSEvent) {
        guard let r = currentRect else { return }
        let quick = e.modifierFlags.contains(.shift)
        machine.handle(.dragEnded(rect: r, quickModifier: quick))
        evaluate()
    }

    override func keyDown(with e: NSEvent) {
        switch e.keyCode {
        case 53: machine.handle(.cancel); evaluate()        // Esc
        case 36, 76: machine.handle(.confirm); evaluate()   // Return / keypad Enter
        default: break
        }
    }

    private func evaluate() {
        switch machine.phase {
        case .recording(let r): onRecord?(r)
        case .cancelled: onCancel?()
        case .idle: currentRect = nil; needsDisplay = true   // tiny drag reset
        default: needsDisplay = true                         // confirming: keep box + glow
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.30).setFill()
        bounds.fill()

        let hint = "Drag to select   ·   Enter to record   ·   hold Shift to record instantly   ·   Esc to cancel"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.85),
        ]
        let hs = hint.size(withAttributes: attrs)
        hint.draw(at: NSPoint(x: bounds.midX - hs.width / 2, y: bounds.maxY - 60), withAttributes: attrs)

        guard let r = currentRect, r.width > 0, r.height > 0 else { return }
        if let ctx = NSGraphicsContext.current?.cgContext { ctx.clear(r) }   // see-through hole

        let confirming: Bool = { if case .confirming = machine.phase { return true }; return false }()
        let stroke = confirming ? NSColor.systemBlue : NSColor.white

        if confirming, let ctx = NSGraphicsContext.current?.cgContext {
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 14, color: NSColor.systemBlue.withAlphaComponent(0.9).cgColor)
            stroke.setStroke()
            let path = NSBezierPath(rect: r); path.lineWidth = 2; path.stroke()
            ctx.restoreGState()
        } else {
            stroke.setStroke()
            let path = NSBezierPath(rect: r); path.lineWidth = 1.5; path.stroke()
        }

        let label = "\(Int(r.width)) × \(Int(r.height))"
        let lattrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        label.draw(at: NSPoint(x: r.minX + 2, y: r.maxY + 4), withAttributes: lattrs)
    }
}
