import Foundation
import AppKit
import ScreenCaptureKit
import SwiftUI
import Vision

enum Keychain {
    static func get(_ service: String, account: String = "default") -> String? {
        var out: AnyObject?
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    /// Stores the value in place of the old one. Returns false when the Keychain refuses, and then the old value stays.
    static func set(_ value: String, _ service: String, account: String = "default") -> Bool {
        guard !value.isEmpty else { delete(service, account: account); return true }
        let match: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        let data = Data(value.utf8)
        if SecItemCopyMatching(match as CFDictionary, nil) == errSecSuccess {
            return SecItemUpdate(match as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecSuccess
        }
        var add = match
        add[kSecValueData as String] = data
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func delete(_ service: String, account: String = "default") {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] as CFDictionary)
    }
}
