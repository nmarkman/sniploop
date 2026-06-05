import AppKit
import SniploopCore

/// A small preferences window. Edits are saved immediately via `onChange`.
final class SettingsWindowController: NSObject {
    private let window: NSWindow
    private var settings: Settings
    private let onChange: (Settings) -> Void

    private let formatPopup = NSPopUpButton()
    private let fpsPopup = NSPopUpButton()
    private let folderLabel = NSTextField(labelWithString: "")
    private let cursorCheck = NSButton(checkboxWithTitle: "Show cursor in capture", target: nil, action: nil)

    private let fpsOptions = [10, 15, 24, 30]

    init(settings: Settings, onChange: @escaping (Settings) -> Void) {
        self.settings = settings
        self.onChange = onChange
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 220),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Sniploop Settings"
        window.isReleasedWhenClosed = false
        super.init()
        buildUI()
        syncFromSettings()
    }

    func showWindow() {
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func buildUI() {
        formatPopup.addItems(withTitles: OutputFormat.allCases.map { $0.label })
        formatPopup.target = self; formatPopup.action = #selector(changed)
        fpsPopup.addItems(withTitles: fpsOptions.map { "\($0) fps" })
        fpsPopup.target = self; fpsPopup.action = #selector(changed)
        cursorCheck.target = self; cursorCheck.action = #selector(changed)
        folderLabel.lineBreakMode = .byTruncatingMiddle
        folderLabel.textColor = .secondaryLabelColor
        folderLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let chooseButton = NSButton(title: "Choose…", target: self, action: #selector(chooseFolder))
        chooseButton.bezelStyle = .rounded

        let folderRow = NSStackView(views: [folderLabel, chooseButton])
        folderRow.orientation = .horizontal
        folderRow.spacing = 8

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Save as:"), formatPopup],
            [NSTextField(labelWithString: "Frame rate:"), fpsPopup],
            [NSTextField(labelWithString: "Save to:"), folderRow],
            [NSGridCell.emptyContentView, cursorCheck],
        ])
        grid.rowSpacing = 14
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            grid.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20),
        ])
        window.contentView = content
    }

    private func syncFromSettings() {
        formatPopup.selectItem(at: OutputFormat.allCases.firstIndex(of: settings.defaultFormat) ?? 0)
        fpsPopup.selectItem(at: fpsOptions.firstIndex(of: settings.defaultFPS) ?? 1)
        cursorCheck.state = settings.showCursor ? .on : .off
        folderLabel.stringValue = settings.destinationFolderPath
    }

    @objc private func changed() {
        if formatPopup.indexOfSelectedItem >= 0 {
            settings.defaultFormat = OutputFormat.allCases[formatPopup.indexOfSelectedItem]
        }
        if fpsPopup.indexOfSelectedItem >= 0 {
            settings.defaultFPS = fpsOptions[fpsPopup.indexOfSelectedItem]
        }
        settings.showCursor = (cursorCheck.state == .on)
        onChange(settings)
    }

    @objc private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: settings.destinationFolderPath)
        if panel.runModal() == .OK, let url = panel.url {
            settings.destinationFolderPath = url.path
            folderLabel.stringValue = url.path
            onChange(settings)
        }
    }
}
