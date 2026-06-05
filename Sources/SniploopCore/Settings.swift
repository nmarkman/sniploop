import Foundation

public struct Settings: Codable, Equatable {
    public var destinationFolderPath: String
    public var defaultFPS: Int
    public var defaultMaxWidth: Int?
    public var showCursor: Bool
    public var launchAtLogin: Bool

    public init(destinationFolderPath: String, defaultFPS: Int, defaultMaxWidth: Int?, showCursor: Bool, launchAtLogin: Bool) {
        self.destinationFolderPath = destinationFolderPath
        self.defaultFPS = defaultFPS
        self.defaultMaxWidth = defaultMaxWidth
        self.showCursor = showCursor
        self.launchAtLogin = launchAtLogin
    }

    public static let defaults = Settings(
        destinationFolderPath: NSString(string: "~/Desktop").expandingTildeInPath,
        defaultFPS: 15,
        defaultMaxWidth: 800,
        showCursor: true,
        launchAtLogin: false
    )
}

public protocol SettingsStore: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
}

/// UserDefaults conforms to SettingsStore at the call site in the app target.
public final class SettingsManager {
    private let store: SettingsStore
    private let key = "sniploop.settings.v1"

    public init(store: SettingsStore) { self.store = store }

    public func load() -> Settings {
        guard let data = store.data(forKey: key),
              let s = try? JSONDecoder().decode(Settings.self, from: data) else {
            return .defaults
        }
        return s
    }

    public func save(_ settings: Settings) {
        store.set(try? JSONEncoder().encode(settings), forKey: key)
    }
}
