import CommonCrypto
import CryptoKit
import Foundation

/// The person's keys in a backup, only when they chose it, and never readable without their password (D91):
/// AES-GCM with a 256-bit key derived from the password by PBKDF2-SHA256 (600,000 rounds, a random salt), so a
/// backup file that gets around gives nothing without it. The keys are the providers' (with the host each is bound
/// to) and the MCP servers' environment values.
public enum BackupKeys {
    static let rounds: UInt32 = 600_000
    /// Bound to what it seals: a sealed box from anything else doesn't open as backup keys.
    static let context = Data("Sidefolk backup keys 1".utf8)

    struct Sealed: Codable {
        var kdf = "pbkdf2-sha256"
        var rounds: UInt32
        var salt: String
        var box: String
    }

    /// Every key Sidefolk keeps for these MCP servers and the providers, as saved.
    public static func collect(from store: any SecretStore, mcpServers: [String]) -> [String: String] {
        let accounts = SecretKey.providerKeys.flatMap { [$0, ProviderKeys.bindingKey($0)] } + mcpServers.map(SecretKey.mcpServer)
        var found: [String: String] = [:]
        for account in accounts {
            if let value = try? store.get(account), !value.isEmpty { found[account] = value.reveal() }
        }
        return found
    }

    static func seal(_ keys: [String: String], password: String) throws -> Data {
        var salt = Data(count: 16)
        guard salt.withUnsafeMutableBytes({ SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }) == errSecSuccess else {
            throw UserFacingError("Your keys couldn't be sealed.")
        }
        let key = try derive(password, salt: salt, rounds: rounds)
        let plain = try JSONEncoder().encode(keys)
        guard let combined = try AES.GCM.seal(plain, using: key, authenticating: context).combined else {
            throw UserFacingError("Your keys couldn't be sealed.")
        }
        return try JSONEncoder().encode(Sealed(rounds: rounds, salt: salt.base64EncodedString(), box: combined.base64EncodedString()))
    }

    /// The keys, or an error that says the password is wrong (or the file isn't sealed keys).
    public static func open(_ data: Data, password: String) throws -> [String: String] {
        guard let sealed = try? JSONDecoder().decode(Sealed.self, from: data), sealed.kdf == "pbkdf2-sha256",
              (100_000...10_000_000).contains(sealed.rounds),
              let salt = Data(base64Encoded: sealed.salt), let combined = Data(base64Encoded: sealed.box) else {
            throw UserFacingError("The keys in this backup can't be read.")
        }
        let key = try derive(password, salt: salt, rounds: sealed.rounds)
        guard let box = try? AES.GCM.SealedBox(combined: combined),
              let plain = try? AES.GCM.open(box, using: key, authenticating: context),
              let keys = try? JSONDecoder().decode([String: String].self, from: plain) else {
            throw UserFacingError("That password doesn't open the keys in this backup.", recovery: "Try again, or restore without them.")
        }
        return keys
    }

    /// Puts the keys in the Keychain, replacing those with the same names; only names Sidefolk uses.
    public static func save(_ keys: [String: String], to store: any SecretStore) throws {
        for (account, value) in restorable(keys) { try store.set(account, Secret(value)) }
    }

    /// The keys among these that a restore may write: only names Sidefolk uses.
    static func restorable(_ keys: [String: String]) -> [String: String] { keys.filter { isRestorable($0.key) } }

    static func isRestorable(_ account: String) -> Bool {
        SecretKey.providerKeys.contains { account == $0 || account == ProviderKeys.bindingKey($0) } || account.hasPrefix("mcp.")
    }

    // MARK: What a restore replaced (Undo restore)

    /// The values a restore's keys replaced, so Undo restore can put them back (D91 amended). Sealed with a random key
    /// kept in the Keychain, never in the data folder: the undo folder alone gives nothing, and the Keychain item goes
    /// with it. A value that wasn't there is nil (Undo deletes the key the backup added).
    struct Before: Codable {
        /// The Keychain item holding the sealing key.
        var account: String
        var box: String
    }

    static let undoAccountPrefix = "backup.undo."

    /// Seals the current values of the accounts `keys` would replace into `file`.
    static func keepBefore(_ keys: [String: String], from store: any SecretStore, to file: URL) throws {
        let accounts = restorable(keys).keys
        guard !accounts.isEmpty else { return }
        var old: [String: String?] = [:]
        // `updateValue`: assigning a missing key's nil through the subscript would leave the name out.
        for account in accounts { old.updateValue(try store.get(account)?.reveal(), forKey: account) }
        let key = SymmetricKey(size: .bits256)
        let account = undoAccountPrefix + UUID().uuidString
        try store.set(account, Secret(key.withUnsafeBytes { Data($0) }.base64EncodedString()))
        guard let combined = try AES.GCM.seal(try JSONEncoder().encode(old), using: key, authenticating: context).combined else {
            try? store.delete(account)
            throw UserFacingError("Your keys couldn't be sealed.")
        }
        try JSONEncoder().encode(Before(account: account, box: combined.base64EncodedString())).write(to: file, options: .atomic)
    }

    /// Puts back the values `file` kept (deleting keys that weren't there), then forgets them. False when they can't be
    /// read (the Keychain item is gone): the keys are left as they are.
    @discardableResult
    static func putBack(from file: URL, to store: any SecretStore) -> Bool {
        guard let data = FileManager.default.contents(atPath: file.path),
              let before = try? JSONDecoder().decode(Before.self, from: data) else { return false }
        defer { forget(file, store: store) }
        guard let raw = try? store.get(before.account)?.reveal(), let keyData = Data(base64Encoded: raw),
              let combined = Data(base64Encoded: before.box), let box = try? AES.GCM.SealedBox(combined: combined),
              let plain = try? AES.GCM.open(box, using: SymmetricKey(data: keyData), authenticating: context),
              let old = try? JSONDecoder().decode([String: String?].self, from: plain) else {
            Log.shared.warning("backup", "the keys from before the restore couldn't be read")
            return false
        }
        for (account, value) in old where isRestorable(account) {
            if let value { try? store.set(account, Secret(value)) } else { try? store.delete(account) }
        }
        return true
    }

    /// Deletes the kept values and their sealing key.
    static func forget(_ file: URL, store: any SecretStore) {
        if let data = FileManager.default.contents(atPath: file.path), let before = try? JSONDecoder().decode(Before.self, from: data),
           before.account.hasPrefix(undoAccountPrefix) {
            try? store.delete(before.account)
        }
        try? FileManager.default.removeItem(at: file)
    }

    private static func derive(_ password: String, salt: Data, rounds: UInt32) throws -> SymmetricKey {
        var out = Data(count: 32)
        let utf8 = Array(password.utf8)
        let status = out.withUnsafeMutableBytes { key in
            salt.withUnsafeBytes { s in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), password, utf8.count,
                                     s.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                     CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds,
                                     key.bindMemory(to: UInt8.self).baseAddress, 32)
            }
        }
        guard status == kCCSuccess else { throw UserFacingError("Your keys couldn't be sealed.") }
        return SymmetricKey(data: out)
    }
}
