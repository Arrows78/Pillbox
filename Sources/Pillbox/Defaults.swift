import Foundation

enum Defaults {
    /// A Bool preference that falls back to `value` while the key was never set (`UserDefaults.bool` alone says false).
    static func bool(_ key: String, default value: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? value
    }
}
