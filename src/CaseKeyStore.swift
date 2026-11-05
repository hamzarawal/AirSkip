import Foundation
import Security
import LocalAuthentication

enum CaseKeyStore {
    private static let service = "local.airskip.case-encryption-key"

    enum Failure: LocalizedError {
        case unavailable, malformed, keychain(OSStatus)
        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "No paired AirPods key was found. Connect your AirPods to this Mac and try again, or import MagicAccEncKey manually."
            case .malformed:
                return "This Keychain item does not contain a valid AirPods encryption key."
            case .keychain(let status):
                if status == errSecUserCanceled || status == errSecAuthFailed {
                    return "Keychain access was not approved. You can retry when ready."
                }
                return "Keychain could not provide the key (error \(status)). Try manual import from Keychain Access."
            }
        }
    }

    /// Read only the selected device during setup or an explicit troubleshooting retry.
    /// Query that device's MobileBluetooth entry only; never dump the Keychain.
    static func loadPairedKey(address: String) throws -> Data {
        var keychain: SecKeychain?
        let status = SecKeychainOpen("/Library/Keychains/System.keychain", &keychain)
        guard status == errSecSuccess, let keychain else { throw Failure.keychain(status) }
        let accounts = [address.uppercased(), address.lowercased(),
                        address.replacingOccurrences(of: ":", with: "-").lowercased()]
        for account in accounts {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "MobileBluetooth",
                kSecAttrAccount as String: account,
                kSecMatchSearchList as String: [keychain],
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            var result: CFTypeRef?
            let resultStatus = SecItemCopyMatching(query as CFDictionary, &result)
            if resultStatus == errSecItemNotFound { continue }
            guard resultStatus == errSecSuccess else { throw Failure.keychain(resultStatus) }
            guard let data = result as? Data,
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
                  let dictionary = plist as? [String: Any],
                  let text = dictionary["MagicAccEncKey"] as? String,
                  let key = AirPodsKey.parse(text)
            else { throw Failure.malformed }
            return key
        }
        throw Failure.unavailable
    }

    static func loadSavedKey(address: String = "", allowPrompt: Bool = true) throws -> Data? {
        var result: CFTypeRef?
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: address.isEmpty ? "case" : address,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if !allowPrompt {
            let context = LAContext()
            context.interactionNotAllowed = true
            query[kSecUseAuthenticationContext as String] = context
        }
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if !allowPrompt, status == errSecInteractionNotAllowed { return nil }
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Failure.keychain(status) }
        guard let data = result as? Data, data.count == 16 else { throw Failure.malformed }
        return data
    }

    static func save(_ key: Data, address: String = "") throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: address.isEmpty ? "case" : address
        ]
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: key] as CFDictionary)
        if update == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = key
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let status = SecItemAdd(item as CFDictionary, nil)
            guard status == errSecSuccess else { throw Failure.keychain(status) }
        } else if update != errSecSuccess { throw Failure.keychain(update) }
    }

    static func forget(address: String = "") throws {
        let status = SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: address.isEmpty ? "case" : address
        ] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure.keychain(status) }
    }
}
