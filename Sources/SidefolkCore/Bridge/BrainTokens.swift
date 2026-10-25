import Darwin
import Foundation
import Security
import Synchronization

/// Maps per-run brain tokens to the run's toolbox, so tool calls that arrive over the socket from
/// the Claude Code brain run as `Caller.agent(runId)` with that run's taint (SECURITY.md T6).
/// A token is valid only while registered, binds to the first connection that presents it, and is
/// compared in constant time.
public final class BrainTokenRegistry: RunTokenRegistry, Sendable {
    private struct Entry {
        var token: [UInt8]
        var toolbox: BrainToolbox
        var connection: UInt64?
    }

    private let entries = Mutex<[Entry]>([])

    public init() {}

    /// 32 random bytes from the system CSPRNG, hex encoded.
    public static func makeToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    public func register(token: String, toolbox: BrainToolbox) {
        let bytes = Array(token.utf8)
        entries.withLock { $0.removeAll { Self.equal($0.token, bytes) }; $0.append(Entry(token: bytes, toolbox: toolbox)) }
    }

    public func unregister(token: String) {
        let bytes = Array(token.utf8)
        entries.withLock { $0.removeAll { Self.equal($0.token, bytes) } }
    }

    /// The toolbox for `token` if it is registered and not bound to another connection; binds it.
    func claim(_ token: String, connection: UInt64) -> BrainToolbox? {
        let bytes = Array(token.utf8)
        return entries.withLock { list -> BrainToolbox? in
            guard let i = list.firstIndex(where: { Self.equal($0.token, bytes) }) else { return nil }
            if let bound = list[i].connection, bound != connection { return nil }
            list[i].connection = connection
            return list[i].toolbox
        }
    }

    /// Still registered and bound to this connection (it stops being valid at unregister).
    func isBound(_ token: String, to connection: UInt64) -> Bool {
        let bytes = Array(token.utf8)
        return entries.withLock { list in list.contains { Self.equal($0.token, bytes) && $0.connection == connection } }
    }

    var count: Int { entries.withLock { $0.count } }

    /// Constant time for equal lengths; tokens all have the same public length.
    private static func equal(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        guard a.count == b.count, !a.isEmpty else { return false }
        return a.withUnsafeBytes { pa in b.withUnsafeBytes { pb in timingsafe_bcmp(pa.baseAddress, pb.baseAddress, a.count) == 0 } }
    }
}
