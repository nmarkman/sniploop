import AppKit
import SniploopCore

final class AppController: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var hotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let mb = MenuBarController()
        mb.onNewCapture = { [weak self] in self?.startCapture() }
        mb.onQuit = { NSApp.terminate(nil) }
        menuBar = mb
        hotKey = GlobalHotKey.defaultCapture { [weak self] in self?.startCapture() }
    }

    func startCapture() {
        // Wired in later tasks. For now, prove the entry point fires.
        NSLog("Sniploop: startCapture invoked")
    }

    // URL scheme: sniploop://capture
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where URLTrigger.action(from: url) == .newCapture {
            startCapture()
        }
    }
}
