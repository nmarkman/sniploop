/// Which file(s) a capture produces. Default is GIF (the core product); MP4 and Both are options.
public enum OutputFormat: String, Codable, CaseIterable {
    case gif
    case mp4
    case both

    public var producesGIF: Bool { self == .gif || self == .both }
    public var producesMP4: Bool { self == .mp4 || self == .both }

    /// Human-readable label for UI.
    public var label: String {
        switch self {
        case .gif: return "GIF"
        case .mp4: return "MP4"
        case .both: return "GIF + MP4"
        }
    }
}
