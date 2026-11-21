import Foundation
import Security

struct SoulseekAccount: Codable {
    let username: String
    let password: String
}

enum SoulseekKeychain {
    static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "local.music.crate.soulseek",
        kSecAttrAccount as String: "Soulseek"
    ]

    static func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: SecCopyErrorMessageString(status, nil) as String? ?? "Could not access macOS Keychain."
            ])
        }
    }

    static func load(allowInteraction: Bool = true) throws -> SoulseekAccount? {
        var request = query
        // Legacy login-keychain ACLs ignore LAContext's no-UI flag; preserve this existing store.
        var previous: DarwinBoolean = true
        if !allowInteraction {
            try check(SecKeychainGetUserInteractionAllowed(&previous))
            try check(SecKeychainSetUserInteractionAllowed(false))
        }
        defer { if !allowInteraction { SecKeychainSetUserInteractionAllowed(previous.boolValue) } }
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = item as? Data else { return nil }
        return try JSONDecoder().decode(SoulseekAccount.self, from: data)
    }

    static func save(_ account: SoulseekAccount) throws {
        let values = [kSecValueData as String: try JSONEncoder().encode(account)]
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var item = query.merging(values) { _, new in new }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            try check(SecItemAdd(item as CFDictionary, nil))
        } else { try check(status) }
    }

    static func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }
}
