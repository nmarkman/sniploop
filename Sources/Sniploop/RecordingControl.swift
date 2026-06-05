import AppKit

final class RecordingControl: NSObject {
    private let window: NSWindow
    private let timeLabel: NSTextField
    private let started = Date()
    private var timer: Timer?
    var onStop: (() -> Void)?
    var onCancel: (() -> Void)?

    /// `region` is in global screen points (bottom-left origin).
    init(near region: NSRect, on screen: NSScreen) {
        let size = NSSize(width: 184, height: 40)
        var origin = NSPoint(x: region.minX, y: region.maxY + 10)
        if origin.y + size.height > screen.frame.maxY - 6 { origin.y = region.minY - size.height - 10 }
        origin.x = max(screen.frame.minX + 6, min(origin.x, screen.frame.maxX - size.width - 6))
        origin.y = max(screen.frame.minY + 6, origin.y)

        window = NSWindow(contentRect: NSRect(origin: origin, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true

        let bg = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        bg.material = .hudWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 10
        bg.layer?.masksToBounds = true

        timeLabel = NSTextField(labelWithString: "0:00")
        timeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        timeLabel.textColor = .white

        super.init()

        let stop = NSButton(title: "Stop", target: self, action: #selector(stopTapped))
        stop.bezelStyle = .rounded
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancel.bezelStyle = .rounded

        let stack = NSStackView(views: [timeLabel, stop, cancel])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        stack.frame = NSRect(origin: .zero, size: size)
        stack.autoresizingMask = [.width, .height]
        bg.addSubview(stack)
        window.contentView = bg

        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func show() { window.orderFrontRegardless() }
    func close() { timer?.invalidate(); window.orderOut(nil) }

    private func tick() {
        let s = Int(Date().timeIntervalSince(started))
        timeLabel.stringValue = String(format: "%d:%02d", s / 60, s % 60)
    }

    @objc private func stopTapped() { onStop?() }
    @objc private func cancelTapped() { onCancel?() }
}
