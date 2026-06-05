import Foundation

public enum TriggerAction: Equatable {
    case newCapture
}

public enum URLTrigger {
    public static func action(from url: URL) -> TriggerAction? {
        guard url.scheme == "sniploop" else { return nil }
        switch url.host {
        case "capture": return .newCapture
        default: return nil
        }
    }
}
