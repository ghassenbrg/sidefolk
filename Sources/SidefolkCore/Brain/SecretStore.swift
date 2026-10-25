import Foundation
import Security
import Synchronization

/// A credential that never shows itself: printing, dumping or encoding it yields "[redacted]".
/// Only `reveal()` returns the value, and only adapters building a request header call it.
public struct Secret: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable, Encodable {
    private let value: String

    public init(_ value: String) { self.value = value.trimmingCharacters(in: .whitespacesAndNewlines) }

    public func reveal() -> String { value }
    public var isEmpty: Bool { value.isEmpty }

    public var description: String { "[redacted]" }
    public var debugDescription: String { "Secret([redacted])" }
    public var customMirror: Mirror { Mirror(self, children: [], displayStyle: .struct) }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode("[redacted]")
    }
}

/// Where API keys live. Values never go to SQLite, UserDefaults, argv, child environments or logs.
public protocol SecretStore: Sendable {
    func get(_ key: String) throws -> Secret?
    func set(_ key: String, _ value: Secret) throws
    func delete(_ key: String) throws
}

public enum SecretKey {
    public static let anthropicAPIKey = "anthropic.apiKey"
    public static let openAIAPIKey = "openai.apiKey"
}

public struct SecretStoreError: Error, Sendable, CustomStringConvertible {
    public var status: OSStatus
    public var description: String { "Keychain error \(status)" }
}

/// Generic-password items in the login Keychain, readable after first unlock, never synced.
/// Debug builds use their own service so ad-hoc builds never touch the release app's items.
public struct KeychainSecretStore: SecretStore {
    public static var defaultService: String {
        #if DEBUG
        "app.sidefolk.secrets.dev"
        #else
        "app.sidefolk.secrets"
        #endif
    }

    public let service: String

    public init(service: String = KeychainSecretStore.defaultService) { self.service = service }

    public func get(_ key: String) throws -> Secret? {
        var query = Self.itemQuery(service: service, key: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw SecretStoreError(status: status) }
        return Secret(String(decoding: data, as: UTF8.self))
    }

    public func set(_ key: String, _ value: Secret) throws {
        let data = Data(value.reveal().utf8)
        let query = Self.itemQuery(service: service, key: key)
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw SecretStoreError(status: update) }
        let added = SecItemAdd(Self.addAttributes(service: service, key: key, data: data) as CFDictionary, nil)
        guard added == errSecSuccess else { throw SecretStoreError(status: added) }
    }

    public func delete(_ key: String) throws {
        let status = SecItemDelete(Self.itemQuery(service: service, key: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SecretStoreError(status: status) }
    }

    static func itemQuery(service: String, key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: false,
        ]
    }

    static func addAttributes(service: String, key: String, data: Data) -> [String: Any] {
        var attributes = itemQuery(service: service, key: key)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        attributes[kSecAttrLabel as String] = "Sidefolk: \(key)"
        return attributes
    }
}

/// For tests and previews.
public final class InMemorySecretStore: SecretStore {
    private let values = Mutex<[String: Secret]>([:])

    public init(_ initial: [String: Secret] = [:]) { values.withLock { $0 = initial } }

    public func get(_ key: String) throws -> Secret? { values.withLock { $0[key] } }
    public func set(_ key: String, _ value: Secret) throws { values.withLock { $0[key] = value } }
    public func delete(_ key: String) throws { _ = values.withLock { $0.removeValue(forKey: key) } }
}

/// API keys bound to the host they were entered for. A key saved for one address is never sent to
/// another: changing an OpenAI-compatible base URL to a new host needs the key entered again.
public struct ProviderKeys: Sendable {
    public static let anthropicHost = "api.anthropic.com"
    public let store: any SecretStore

    public init(store: any SecretStore) { self.store = store }

    /// Saves `key` for `host` (from `ProviderKeys.host(of:)`), replacing any earlier binding.
    public func save(_ key: Secret, account: String, host: String) throws {
        try store.set(account, key)
        try store.set(Self.bindingKey(account), Secret(host.lowercased()))
    }

    public func remove(account: String) throws {
        try store.delete(account)
        try store.delete(Self.bindingKey(account))
    }

    /// The key for `account`, if one is saved. Throws when it was saved for a different host.
    public func key(account: String, host: String) throws(UserFacingError) -> Secret? {
        let saved: Secret?
        let bound: Secret?
        do {
            saved = try store.get(account)
            bound = try store.get(Self.bindingKey(account))
        } catch {
            throw UserFacingError("I couldn't read your API key from the Keychain. Nothing was changed.",
                                  recovery: "Open Settings › AI and paste the key again.", detail: String(describing: error))
        }
        guard let saved, !saved.isEmpty else { return nil }
        // The Anthropic host is fixed, so a key saved without a binding can only be meant for it.
        let boundHost = bound?.reveal() ?? (account == SecretKey.anthropicAPIKey ? Self.anthropicHost : "")
        guard boundHost == host.lowercased() else {
            throw UserFacingError("Your API key was saved for a different address, so I didn't send it. Nothing was changed.",
                                  recovery: "Paste the key again in Settings › AI to use it with \(host).")
        }
        return saved
    }

    /// "api.openai.com", "localhost:11434".
    public static func host(of url: URL) -> String {
        let host = (url.host ?? "").lowercased()
        return url.port.map { "\(host):\($0)" } ?? host
    }

    static func bindingKey(_ account: String) -> String { "\(account).host" }
}
