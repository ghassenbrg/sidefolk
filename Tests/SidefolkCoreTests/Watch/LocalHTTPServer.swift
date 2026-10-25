import Darwin
import Foundation
import Synchronization
import Testing
@testable import SidefolkCore

/// A tiny HTTP server on 127.0.0.1 (nothing leaves the machine), one connection at a time.
final class LocalHTTPServer: @unchecked Sendable {
    struct Request: Sendable { var line: String; var headers: [String: String] }

    let port: UInt16
    private let listener: Int32
    private let handler: @Sendable (Request) -> Data
    private let seen = Mutex<[Request]>([])

    var requests: [Request] { seen.withLock { $0 } }

    init(handler: @escaping @Sendable (Request) -> Data) throws {
        self.handler = handler
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { throw POSIXError(.EIO) }
        var yes: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0, listen(sock, 8) == 0 else { throw POSIXError(.EADDRINUSE) }
        var assigned = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &assigned) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(sock, $0, &length) }
        }
        port = UInt16(bigEndian: assigned.sin_port)
        listener = sock
        Thread.detachNewThread { [self] in serve(sock) }
    }

    func stop() { shutdown(listener, SHUT_RDWR); close(listener) }

    private func serve(_ fd: Int32) {
        while true {
            let client = accept(fd, nil, nil)
            if client < 0 { return }
            var on: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            var head = Data()
            var byte = [UInt8](repeating: 0, count: 1)
            while head.count < 16_384, !head.suffix(4).elementsEqual([13, 10, 13, 10]) {
                guard read(client, &byte, 1) == 1 else { break }
                head.append(byte[0])
            }
            let lines = String(decoding: head, as: UTF8.self).components(separatedBy: "\r\n")
            var headers: [String: String] = [:]
            for line in lines.dropFirst() {
                if let colon = line.firstIndex(of: ":") {
                    headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                }
            }
            let request = Request(line: lines.first ?? "", headers: headers)
            seen.withLock { $0.append(request) }
            let response = handler(request)
            response.withUnsafeBytes { raw in
                var sent = 0
                while sent < raw.count {
                    let n = write(client, raw.baseAddress! + sent, raw.count - sent)
                    if n <= 0 { break }
                    sent += n
                }
            }
            close(client)
        }
    }

    static func response(_ status: Int = 200, _ headers: [String: String] = [:], body: Data = Data(), contentType: String? = "text/html; charset=utf-8") -> Data {
        var text = "HTTP/1.1 \(status) \(HTTPURLResponse.localizedString(forStatusCode: status))\r\n"
        var all = headers
        if let contentType { all["Content-Type"] = contentType }
        all["Content-Length"] = "\(body.count)"
        all["Connection"] = "close"
        for (k, v) in all { text += "\(k): \(v)\r\n" }
        return Data((text + "\r\n").utf8) + body
    }

    static func response(_ headers: [String: String], body: Data = Data(), contentType: String? = "text/html; charset=utf-8") -> Data {
        response(200, headers, body: body, contentType: contentType)
    }
}
