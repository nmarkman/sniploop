import AppKit
import SniploopCore

enum Output {
    /// Move a produced file into the destination folder under a timestamped name; returns the final URL.
    static func save(_ produced: URL, toFolder folder: String, ext: String) throws -> URL {
        let dir = URL(fileURLWithPath: NSString(string: folder).expandingTildeInPath, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(OutputNaming.filename(date: Date(), ext: ext))
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: produced, to: dest)
        return dest
    }

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Put an animated GIF on the pasteboard (data + a file URL for apps that prefer files).
    static func copyGIFToClipboard(_ url: URL) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let gifType = NSPasteboard.PasteboardType("com.compuserve.gif")
        if let data = try? Data(contentsOf: url) {
            pb.setData(data, forType: gifType)
        }
        pb.writeObjects([url as NSURL])
    }
}
