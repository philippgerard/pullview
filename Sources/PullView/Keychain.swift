import Foundation
import Security

/// The personal access token lives in the login keychain, never in UserDefaults.
enum Keychain {
    private static var item: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "io.github.philippgerard.pullview",
         kSecAttrAccount as String: "github-token"]
    }

    static func read() -> String? {
        var query = item
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Replaces the stored token; an empty string deletes it.
    static func write(_ token: String) -> Bool {
        SecItemDelete(item as CFDictionary)
        guard !token.isEmpty else { return true }
        var attributes = item
        attributes[kSecValueData as String] = Data(token.utf8)
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }
}
