import Foundation
import SniploopCore

private final class MemoryStore: SettingsStore {
    var storage: [String: Data] = [:]
    func data(forKey key: String) -> Data? { storage[key] }
    func set(_ data: Data?, forKey key: String) { storage[key] = data }
}

func runSettingsTests() {
    let mgr = SettingsManager(store: MemoryStore())
    T.ok(mgr.load() == Settings.defaults, "load returns defaults when empty")

    let mgr2 = SettingsManager(store: MemoryStore())
    var s = Settings.defaults
    s.defaultFPS = 24
    s.defaultMaxWidth = 640
    s.showCursor = false
    mgr2.save(s)
    T.ok(mgr2.load() == s, "save then load round-trips")

    T.eq(Settings.defaults.defaultFPS, 15, "default fps is 15")
    T.ok(Settings.defaults.showCursor, "default showCursor is true")
}
