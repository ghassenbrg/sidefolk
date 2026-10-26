import Foundation
import Synchronization

/// All tools Sidefolk can run right now: built-in ones plus those contributed by extensions.
public final class ToolRegistry: Sendable {
    private let tools = Mutex<[String: any Tool]>([:])
    private let owners = Mutex<[String: String]>([:])

    public init() {}

    public func register(_ tool: any Tool, owner: String = "builtin") {
        tools.withLock { $0[tool.spec.name] = tool }
        owners.withLock { $0[tool.spec.name] = owner }
    }

    public func register(_ list: [any Tool], owner: String = "builtin") {
        for t in list { register(t, owner: owner) }
    }

    /// Removes every tool an owner (an extension) contributed.
    public func unregister(owner: String) {
        let names = owners.withLock { o in o.filter { $0.value == owner }.map(\.key) }
        tools.withLock { t in for n in names { t[n] = nil } }
        owners.withLock { o in for n in names { o[n] = nil } }
    }

    public func tool(named name: String) -> (any Tool)? {
        tools.withLock { t in t[name] ?? t.values.first { $0.spec.modelName == name } }
    }

    public func owner(of name: String) -> String? { owners.withLock { $0[name] } }

    public var all: [any Tool] { tools.withLock { Array($0.values) }.sorted { $0.spec.name < $1.spec.name } }
    public var specs: [ToolSpec] { all.map(\.spec) }
}
