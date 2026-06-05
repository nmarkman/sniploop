// gifcap: throwaway feel-test for a fast region GIF recorder.
// Launch -> drag a region -> records in the background -> click Stop -> .gif on Desktop.
// Single file, no Xcode. Build with ./build.sh.

import Cocoa
import ScreenCaptureKit
import CoreMedia
import CoreVideo
import CoreImage
import ImageIO
import UniformTypeIdentifiers

// MARK: - Frame storage (thread-safe; the capture callback runs off the main thread)

final class FrameStore {
    private let lock = NSLock()
    private var items: [(image: CGImage, time: Double)] = []

    var count: Int { lock.lock(); defer { lock.unlock() }; return items.count }

    func add(_ image: CGImage, _ time: Double) {
        lock.lock(); items.append((image, time)); lock.unlock()
    }

    func snapshot() -> [(image: CGImage, time: Double)] {
        lock.lock(); defer { lock.unlock() }; return items
    }
}

// MARK: - Recorder (ScreenCaptureKit -> cropped CGImages)

final class Recorder: NSObject, SCStreamOutput {
    private var stream: SCStream?
    private let store = FrameStore()
    private let ciContext = CIContext(options: nil)
    private let queue = DispatchQueue(label: "gifcap.capture")
    private var cropRect: CGRect = .zero
    private let maxFrames = 900   // ~75s at 12fps; keeps memory sane for a POC

    /// `selection` is in points, relative to the captured screen's own frame (bottom-left origin).
    func start(screen: NSScreen, selection: NSRect) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? CGMainDisplayID()
        guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
            throw NSError(domain: "gifcap", code: 1, userInfo: [NSLocalizedDescriptionKey: "No capturable display found"])
        }

        let scale = screen.backingScaleFactor
        let pixelW = Int((screen.frame.width * scale).rounded())
        let pixelH = Int((screen.frame.height * scale).rounded())

        // Convert selection (points, bottom-left) -> pixel crop rect (top-left origin, matches CGImage).
        let cx = (selection.minX * scale).rounded(.down)
        let cy = ((screen.frame.height - selection.maxY) * scale).rounded(.down)
        let cw = (selection.width * scale).rounded(.down)
        let ch = (selection.height * scale).rounded(.down)
        cropRect = CGRect(x: cx, y: cy, width: cw, height: ch)

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = pixelW
        config.height = pixelH
        config.minimumFrameInterval = CMTime(value: 1, timescale: 12)
        config.queueDepth = 6
        config.showsCursor = true
        config.pixelFormat = kCVPixelFormatType_32BGRA

        let s = SCStream(filter: filter, configuration: config, delegate: nil)
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await s.startCapture()
        stream = s
    }

    func stop() async -> [(image: CGImage, time: Double)] {
        if let s = stream { try? await s.stopCapture() }
        stream = nil
        return store.snapshot()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, store.count < maxFrames, sampleBuffer.isValid else { return }

        // Only keep frames the system marks complete (skip idle/blank frames).
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let info = attachments.first,
              let statusRaw = info[.status] as? Int,
              let status = SCFrameStatus(rawValue: statusRaw),
              status == .complete else { return }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ci = CIImage(cvImageBuffer: pixelBuffer)
        guard let full = ciContext.createCGImage(ci, from: ci.extent) else { return }

        let bounds = CGRect(x: 0, y: 0, width: full.width, height: full.height)
        let crop = cropRect.intersection(bounds)
        guard !crop.isNull, crop.width >= 1, crop.height >= 1, let cropped = full.cropping(to: crop) else { return }

        let t = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        store.add(cropped, t)
    }
}

// MARK: - GIF writing (real per-frame delays from capture timestamps)

func writeGIF(_ frames: [(image: CGImage, time: Double)], to url: URL) -> Bool {
    guard frames.count > 0,
          let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil)
    else { return false }

    let fileProps = [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: 0]]
    CGImageDestinationSetProperties(dest, fileProps as CFDictionary)

    for i in 0..<frames.count {
        var delay = 1.0 / 12.0
        if i < frames.count - 1 {
            delay = frames[i + 1].time - frames[i].time
        }
        delay = min(max(delay, 0.02), 1.0)
        let frameProps = [kCGImagePropertyGIFDictionary as String: [
            kCGImagePropertyGIFDelayTime as String: delay,
            kCGImagePropertyGIFUnclampedDelayTime as String: delay
        ]]
        CGImageDestinationAddImage(dest, frames[i].image, frameProps as CFDictionary)
    }
    return CGImageDestinationFinalize(dest)
}

// MARK: - Selection overlay (the Cmd-Shift-4 feel)

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class OverlayView: NSView {
    var onComplete: ((NSRect) -> Void)?
    var onCancel: (() -> Void)?
    private var start: NSPoint?
    private var sel: NSRect?

    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func mouseDown(with e: NSEvent) {
        start = convert(e.locationInWindow, from: nil)
        sel = NSRect(origin: start!, size: .zero)
        needsDisplay = true
    }

    override func mouseDragged(with e: NSEvent) {
        guard let s = start else { return }
        let p = convert(e.locationInWindow, from: nil)
        sel = NSRect(x: min(s.x, p.x), y: min(s.y, p.y), width: abs(p.x - s.x), height: abs(p.y - s.y))
        needsDisplay = true
    }

    override func mouseUp(with e: NSEvent) {
        guard let r = sel, r.width >= 5, r.height >= 5 else { onCancel?(); return }
        onComplete?(r)
    }

    override func keyDown(with e: NSEvent) {
        if e.keyCode == 53 { onCancel?() }   // Esc
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.30).setFill()
        bounds.fill()

        let hint = "Drag to select an area to record   ·   Esc to cancel"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.85)
        ]
        let hsize = hint.size(withAttributes: attrs)
        hint.draw(at: NSPoint(x: bounds.midX - hsize.width / 2, y: bounds.maxY - 60), withAttributes: attrs)

        guard let r = sel, r.width > 0, r.height > 0 else { return }
        if let ctx = NSGraphicsContext.current?.cgContext { ctx.clear(r) }   // punch a see-through hole

        NSColor.white.setStroke()
        let path = NSBezierPath(rect: r)
        path.lineWidth = 1.5
        path.stroke()

        let label = "\(Int(r.width)) × \(Int(r.height))"
        let lattrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        label.draw(at: NSPoint(x: r.minX + 2, y: r.maxY + 4), withAttributes: lattrs)
    }
}

// MARK: - Floating Stop pill (no extra permissions, like Giphy Capture)

final class StopController: NSObject {
    let window: NSWindow
    private let timeLabel: NSTextField
    private let started = Date()
    private var timer: Timer?
    var onStop: (() -> Void)?

    init(near rect: NSRect, on screen: NSScreen) {
        let size = NSSize(width: 132, height: 38)

        // Place just above the region; fall back to below if there's no room.
        var origin = NSPoint(x: rect.minX, y: rect.maxY + 10)
        if origin.y + size.height > screen.frame.maxY - 6 { origin.y = rect.minY - size.height - 10 }
        origin.x = max(screen.frame.minX + 6, min(origin.x, screen.frame.maxX - size.width - 6))
        origin.y = max(screen.frame.minY + 6, origin.y)

        window = NSWindow(contentRect: NSRect(origin: origin, size: size),
                          styleMask: .borderless, backing: .buffered, defer: false)
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

        let button = NSButton(title: "  Stop", target: self, action: #selector(stopTapped))
        button.bezelStyle = .rounded
        button.contentTintColor = .systemRed
        button.image = dotImage()
        button.imagePosition = .imageLeading

        let stack = NSStackView(views: [button, timeLabel])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 12)
        stack.frame = NSRect(origin: .zero, size: size)
        bg.addSubview(stack)
        stack.autoresizingMask = [.width, .height]

        window.contentView = bg

        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func show() { window.orderFrontRegardless() }

    func invalidate() { timer?.invalidate(); window.orderOut(nil) }

    private func dotImage() -> NSImage {
        let img = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        return img
    }

    private func tick() {
        let s = Int(Date().timeIntervalSince(started))
        timeLabel.stringValue = String(format: "%d:%02d", s / 60, s % 60)
    }

    @objc private func stopTapped() { onStop?() }
}

// MARK: - App flow

final class AppController: NSObject, NSApplicationDelegate {
    private let recorder = Recorder()
    private var overlay: OverlayWindow?
    private var stop: StopController?
    private var captureScreen: NSScreen?

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)
        showOverlay()
    }

    private func showOverlay() {
        guard let screen = NSScreen.main else { NSApp.terminate(nil); return }
        captureScreen = screen

        let win = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        win.level = .screenSaver
        win.isOpaque = false
        win.backgroundColor = .clear
        win.ignoresMouseEvents = false
        win.setFrame(screen.frame, display: true)

        let view = OverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.onComplete = { [weak self] r in self?.startRecording(selection: r) }
        view.onCancel = { NSApp.terminate(nil) }
        win.contentView = view

        overlay = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        win.makeFirstResponder(view)
    }

    private func startRecording(selection: NSRect) {
        guard let screen = captureScreen else { return }
        overlay?.orderOut(nil)
        overlay = nil

        // Global coords for placing the Stop pill (view coords are relative to this screen's frame).
        let global = NSRect(x: selection.minX + screen.frame.minX,
                            y: selection.minY + screen.frame.minY,
                            width: selection.width, height: selection.height)
        let sc = StopController(near: global, on: screen)
        sc.onStop = { [weak self] in self?.finishRecording() }
        sc.show()
        stop = sc

        Task {
            do {
                try await recorder.start(screen: screen, selection: selection)
            } catch {
                await MainActor.run { self.failPermission(error) }
            }
        }
    }

    private func finishRecording() {
        stop?.invalidate()
        Task {
            let frames = await recorder.stop()
            let url = self.outputURL()
            let ok = writeGIF(frames, to: url)
            await MainActor.run {
                if ok {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } else {
                    let a = NSAlert()
                    a.messageText = "Nothing captured"
                    a.informativeText = "No frames were recorded. Try again and make sure something on screen changes while recording."
                    a.runModal()
                }
                NSApp.terminate(nil)
            }
        }
    }

    private func outputURL() -> URL {
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd'T'HH.mm.ss"
        return desktop.appendingPathComponent("Capture-\(fmt.string(from: Date())).gif")
    }

    private func failPermission(_ error: Error) {
        stop?.invalidate()
        let a = NSAlert()
        a.messageText = "Can't record the screen"
        a.informativeText = "gifcap needs Screen Recording permission.\n\nOpen System Settings > Privacy & Security > Screen Recording, enable gifcap, then launch it again.\n\n(\(error.localizedDescription))"
        a.addButton(withTitle: "Open Settings")
        a.addButton(withTitle: "Quit")
        if a.runModal() == .alertFirstButtonReturn {
            if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(u)
            }
        }
        NSApp.terminate(nil)
    }
}

// MARK: - main

let app = NSApplication.shared
let controller = AppController()
app.delegate = controller
app.run()
