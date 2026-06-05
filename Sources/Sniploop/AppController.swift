import AppKit
import SniploopCore

final class AppController: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var hotKey: GlobalHotKey?
    private var overlay: OverlayWindow?
    private var captureScreen: NSScreen?

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let mb = MenuBarController()
        mb.onNewCapture = { [weak self] in self?.startCapture() }
        mb.onQuit = { NSApp.terminate(nil) }
        menuBar = mb
        hotKey = GlobalHotKey.defaultCapture { [weak self] in self?.startCapture() }
    }

    func startCapture() {
        guard overlay == nil, let screen = NSScreen.main else { return }
        captureScreen = screen

        let win = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        win.level = .screenSaver
        win.isOpaque = false
        win.backgroundColor = .clear
        win.setFrame(screen.frame, display: true)

        let view = OverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.onRecord = { [weak self] rect in self?.beginRecording(selection: rect) }
        view.onCancel = { [weak self] in self?.dismissOverlay() }
        win.contentView = view

        overlay = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        win.makeFirstResponder(view)
    }

    private func dismissOverlay() {
        overlay?.orderOut(nil)
        overlay = nil
    }

    private func beginRecording(selection: NSRect) {
        dismissOverlay()
        NSLog("Sniploop: beginRecording rect=\(NSStringFromRect(selection))")
    }

    // URL scheme: sniploop://capture
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where URLTrigger.action(from: url) == .newCapture {
            startCapture()
        }
    }
}
