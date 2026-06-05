import Foundation

public enum OutputNaming {
    /// Filename like "Capture-2026-06-05T10.15.30.gif".
    public static func filename(date: Date, ext: String, timeZone: TimeZone = .current) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let stamp = String(format: "%04d-%02d-%02dT%02d.%02d.%02d",
                           c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
        return "Capture-\(stamp).\(ext)"
    }
}
