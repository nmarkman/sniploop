import AppKit
import SniploopCore

final class AppController: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var hotKey: GlobalHotKey?
    private var overlay: OverlayWindow?
    private var captureScreen: NSScreen?
    private let capture = CaptureEngine()
    private var recordingControl: RecordingControl?
    private var lastSelection: NSRect = .zero

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
        guard let screen = captureScreen else { return }
        dismissOverlay()
        lastSelection = selection

        let global = NSRect(x: selection.minX + screen.frame.minX,
                            y: selection.minY + screen.frame.minY,
                            width: selection.width, height: selection.height)
        let control = RecordingControl(near: global, on: screen)
        control.onStop = { [weak self] in self?.finishRecording() }
        control.onCancel = { [weak self] in self?.cancelRecording() }
        control.show()
        recordingControl = control

        Task {
            do {
                try await capture.start(screen: screen, selection: selection, showsCursor: true)
            } catch {
                await MainActor.run { self.failCapture(error) }
            }
        }
    }

    private func finishRecording() {
        recordingControl?.close()
        recordingControl = nil
        Task {
            let url = await capture.stop()
            await MainActor.run {
                if let url { NSLog("Sniploop: master saved at \(url.path)") }
                self.handleMaster(url)
            }
        }
    }

    private func cancelRecording() {
        recordingControl?.close()
        recordingControl = nil
        Task { await capture.cancel() }
    }

    private func handleMaster(_ url: URL?) {
        // Exporter wired in Task 18. For now, reveal the raw master to prove capture works.
        if let url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    private func failCapture(_ error: Error) {
        recordingControl?.close()
        recordingControl = nil
        let a = NSAlert()
        a.messageText = "Can't record the screen"
        a.informativeText = "Sniploop needs Screen Recording permission.\n\nEnable Sniploop under System Settings > Privacy & Security > Screen Recording, then try again.\n\n(\(error.localizedDescription))"
        a.addButton(withTitle: "Open Settings")
        a.addButton(withTitle: "OK")
        if a.runModal() == .alertFirstButtonReturn,
           let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(u)
        }
    }

    // URL scheme: sniploop://capture
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where URLTrigger.action(from: url) == .newCapture {
            startCapture()
        }
    }
}
