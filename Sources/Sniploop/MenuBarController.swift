import AppKit

/// The menu bar status item. Subclasses NSObject so target/action dispatch works.
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    var onNewCapture: (() -> Void)?
    var onSettings: (() -> Void)?
    var onQuit: (() -> Void)?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.dashed.badge.record", accessibilityDescription: "Sniploop")

        let menu = NSMenu()
        let capture = NSMenuItem(title: "New Capture", action: #selector(newCapture), keyEquivalent: "")
        capture.target = self
        menu.addItem(capture)
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(settings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let quitItem = NSMenuItem(title: "Quit Sniploop", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    @objc private func newCapture() { onNewCapture?() }
    @objc private func settings() { onSettings?() }
    @objc private func quit() { onQuit?() }
}
