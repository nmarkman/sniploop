import Foundation
import SniploopCore

/// Backs SettingsManager with the standard user defaults.
final class UserDefaultsSettingsStore: SettingsStore {
    private let defaults = UserDefaults.standard
    func data(forKey key: String) -> Data? { defaults.data(forKey: key) }
    func set(_ data: Data?, forKey key: String) { defaults.set(data, forKey: key) }
}
