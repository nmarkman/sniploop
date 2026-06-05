import AppKit
import AVFoundation
import SniploopCore

final class AppController: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var hotKey: GlobalHotKey?
    private var overlay: OverlayWindow?
    private var captureScreen: NSScreen?
    private let capture = CaptureEngine()
    private let exporter = Exporter()
    private var recordingControl: RecordingControl?
    private var recordingBorder: RecordingBorder?
    private var lastSelection: NSRect = .zero

    private let settingsManager = SettingsManager(store: UserDefaultsSettingsStore())
    private var settings = Settings.defaults
    private var settingsWindow: SettingsWindowController?

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)
        settings = settingsManager.load()
        let mb = MenuBarController()
        mb.onNewCapture = { [weak self] in self?.startCapture() }
        mb.onSettings = { [weak self] in self?.openSettings() }
        mb.onQuit = { NSApp.terminate(nil) }
        menuBar = mb
        hotKey = GlobalHotKey.defaultCapture { [weak self] in self?.startCapture() }
    }

    private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(settings: settings) { [weak self] updated in
                guard let self else { return }
                self.settings = updated
                self.settingsManager.save(updated)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.showWindow()
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

        // Persistent boundary frame around the region. Drawn just OUTSIDE the captured rect,
        // so it stays visible while recording but never appears in the output.
        let border = RecordingBorder(around: global)
        border.show()
        recordingBorder = border

        let control = RecordingControl(near: global, on: screen)
        control.onStop = { [weak self] in self?.finishRecording() }
        control.onCancel = { [weak self] in self?.cancelRecording() }
        control.show()
        recordingControl = control

        Task {
            do {
                try await capture.start(screen: screen, selection: selection, showsCursor: settings.showCursor)
            } catch {
                await MainActor.run { self.failCapture(error) }
            }
        }
    }

    private func closeRecordingChrome() {
        recordingControl?.close()
        recordingControl = nil
        recordingBorder?.close()
        recordingBorder = nil
    }

    private func finishRecording() {
        closeRecordingChrome()
        Task {
            let url = await capture.stop()
            await MainActor.run { self.handleMaster(url) }
        }
    }

    private func cancelRecording() {
        closeRecordingChrome()
        Task { await capture.cancel() }
    }

    private func handleMaster(_ url: URL?) {
        guard let master = url else { return }
        let settings = self.settings
        Task {
            do {
                let movDuration = try await AVURLAsset(url: master).load(.duration).seconds
                let spec = EditSpec.identity(duration: movDuration, fps: settings.defaultFPS)
                var primary: URL?

                if settings.defaultFormat.producesGIF {
                    let gif = try await exporter.exportGIF(master: master, spec: spec)
                    let savedGIF = try Output.save(gif, toFolder: settings.destinationFolderPath, ext: "gif")
                    primary = savedGIF
                    await MainActor.run {
                        Output.copyGIFToClipboard(savedGIF)
                        NSLog("Sniploop: GIF saved + copied at \(savedGIF.path)")
                    }
                }
                if settings.defaultFormat.producesMP4 {
                    let mp4 = try await exporter.exportMP4(master: master, spec: spec)
                    let savedMP4 = try Output.save(mp4, toFolder: settings.destinationFolderPath, ext: "mp4")
                    if primary == nil { primary = savedMP4 }
                    await MainActor.run { NSLog("Sniploop: MP4 saved at \(savedMP4.path)") }
                }
                if let primary {
                    await MainActor.run { Output.reveal(primary) }
                }
                try? FileManager.default.removeItem(at: master)
            } catch {
                await MainActor.run {
                    let a = NSAlert()
                    a.messageText = "Export failed"
                    a.informativeText = "\(error)"
                    a.runModal()
                }
            }
        }
    }

    private func failCapture(_ error: Error) {
        closeRecordingChrome()
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
