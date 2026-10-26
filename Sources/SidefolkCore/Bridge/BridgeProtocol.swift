import Foundation

/// The local API between Sidefolk.app and its helpers (`sidefolk mcp`, `hook`, `run`, `status`):
/// one JSON object per line over a unix socket. Requests are `{"id", "method", "params"}`, replies
/// `{"id", "result"}` or `{"id", "error": {"code", "message"}}`. The first request must be `hello`.
public enum BridgeProtocol {
    /// Bumped on incompatible changes; `hello` refuses a different major version.
    public static let version = 1
    public static let maxLineBytes = 1 << 20

    public enum Method: String, Sendable, CaseIterable {
        case hello
        case toolsList = "tools/list"
        case toolsCall = "tools/call"
        case status
        case sessionEvent = "session/event"
        case jobStart = "job/start"
        case jobFinish = "job/finish"
    }

    /// Error codes sent over the wire. Clients show `message`; codes are for logic and tests.
    public enum Code: String, Sendable {
        case badRequest = "bad_request"
        case helloRequired = "hello_required"
        case version
        case unauthorized
        case notFound = "not_found"
        case rateLimited = "rate_limited"
        case busy
        case tooLarge = "too_large"
        case unavailable
        case internalError = "internal"
    }

    static func request(id: Int, method: String, params: JSONValue) -> JSONValue {
        ["id": .number(Double(id)), "method": .string(method), "params": params]
    }

    static func reply(id: JSONValue, result: JSONValue) -> JSONValue {
        ["id": id, "result": result]
    }

    static func failure(id: JSONValue, _ code: Code, _ message: String) -> JSONValue {
        ["id": id, "error": ["code": .string(code.rawValue), "message": .string(message)]]
    }

    /// One wire line: compact JSON plus the newline. JSONEncoder escapes newlines inside strings.
    static func line(_ value: JSONValue) -> [UInt8] {
        Array(value.jsonString.utf8) + [0x0A]
    }
}

public enum BridgeError: Error, Sendable, Equatable, CustomStringConvertible {
    /// The socket path does not fit in `sun_path` (103 bytes plus NUL).
    case pathTooLong(String)
    /// The run folder or socket is not a private, user-owned location.
    case unsafeLocation(String)
    /// Another Sidefolk is already listening on the socket.
    case alreadyRunning
    /// Nothing is listening (the app isn't running).
    case notRunning
    /// The other end of the socket belongs to a different user.
    case peerRejected
    case system(String, Int32)
    case remote(code: String, message: String)
    case timedOut
    case disconnected

    public var description: String {
        switch self {
        case .pathTooLong(let p): "The socket path is too long (\(p.utf8.count) bytes, at most \(UnixSocket.maxPathBytes))."
        case .unsafeLocation(let why): "Unsafe socket location: \(why)"
        case .alreadyRunning: "Another Sidefolk is already running."
        case .notRunning: "Sidefolk isn't running."
        case .peerRejected: "The socket belongs to another user."
        case .system(let call, let code): "\(call) failed: \(String(cString: strerror(code)))"
        case .remote(_, let message): message
        case .timedOut: "Sidefolk didn't answer in time."
        case .disconnected: "The connection to Sidefolk closed."
        }
    }
}
