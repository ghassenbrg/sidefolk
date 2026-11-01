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
        let allowed = Set(SecretKey.providerKeys.flatMap { [$0, ProviderKeys.bindingKey($0)] })
        for (account, value) in keys where allowed.contains(account) || account.hasPrefix("mcp.") {
            try store.set(account, Secret(value))
        }
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
