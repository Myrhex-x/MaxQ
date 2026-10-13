//
//  GrokKeyStore.swift
//  Max Q
//
//  The user's own SpaceXAI API key, stored in the macOS Keychain and nowhere else. It never
//  touches UserDefaults, logs, or any server other than api.x.ai.
//
//  Every query is scoped by class + service + account. A delete with a broad query can remove
//  unrelated Keychain items (including signing identities), so never loosen these.
//

import Foundation
import Security

enum GrokKeyStore {
    nonisolated static let productionService = "com.myrhex.MaxQ.xai-api-key"
    /// Overridden only by unit tests, so they never touch the real key. A debug copy built under
    /// another bundle ID (a test copy) keeps a key of its own too.
    nonisolated(unsafe) static var service: String = {
        #if DEBUG
        if let id = Bundle.main.bundleIdentifier, id != "com.myrhex.MaxQ" { return id + ".xai-api-key" }
        #endif
        return productionService
    }()
    nonisolated private static let account = "default"

    nonisolated private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    nonisolated static func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data,
              let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }

    @discardableResult
    nonisolated static func save(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return false }
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var add = baseQuery
        add[kSecValueData as String] = data
        add[kSecAttrLabel as String] = "Max Q: SpaceXAI API key"
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    nonisolated static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
