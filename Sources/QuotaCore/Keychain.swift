import Foundation
import Security

/// API keys live only in the login Keychain, never synced to iCloud and never written to disk by Quota.
public struct KeychainStore: SecretStore {
    private let service: String

    public init(service: String = "quota.api-keys") {
        self.service = service
    }

    public func secret(for provider: ProviderID) -> String? {
        var query = baseQuery(provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func hasSecret(for provider: ProviderID) -> Bool {
        var query = baseQuery(provider)
        query[kSecReturnAttributes as String] = true
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    public func setSecret(_ value: String?, for provider: ProviderID) -> Bool {
        SecItemDelete(baseQuery(provider) as CFDictionary)
        guard let value, !value.isEmpty else { return true }
        var add = baseQuery(provider)
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    public func removeAll() {
        for provider in ProviderID.allCases { setSecret(nil, for: provider) }
    }

    private func baseQuery(_ provider: ProviderID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecAttrSynchronizable as String: false,
        ]
    }
}

/// CLI-friendly store: environment variable first, then the Keychain.
public struct EnvironmentOrKeychainStore: SecretStore {
    private let keychain = KeychainStore()

    public init() {}

    public func secret(for provider: ProviderID) -> String? {
        if let env = ProcessInfo.processInfo.environment[provider.keyEnvironmentVariable], !env.isEmpty {
            return env
        }
        return keychain.secret(for: provider)
    }
}
