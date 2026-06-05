import Foundation
import SniploopCore

func runOutputNamingTests() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!

    var c1 = DateComponents()
    c1.year = 2026; c1.month = 6; c1.day = 5; c1.hour = 10; c1.minute = 15; c1.second = 30
    let d1 = cal.date(from: c1)!
    T.eq(OutputNaming.filename(date: d1, ext: "gif", timeZone: TimeZone(identifier: "UTC")!),
         "Capture-2026-06-05T10.15.30.gif", "formats gif filename")

    var c2 = DateComponents()
    c2.year = 2026; c2.month = 1; c2.day = 2; c2.hour = 3; c2.minute = 4; c2.second = 5
    let d2 = cal.date(from: c2)!
    T.eq(OutputNaming.filename(date: d2, ext: "mp4", timeZone: TimeZone(identifier: "UTC")!),
         "Capture-2026-01-02T03.04.05.mp4", "respects extension and zero-pads")
}
