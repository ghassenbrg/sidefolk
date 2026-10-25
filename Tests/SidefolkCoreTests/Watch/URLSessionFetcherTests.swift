import Foundation
import Testing
@testable import SidefolkCore

/// The one test that touches the network stack: a server on 127.0.0.1, nothing leaves the machine.
@Suite struct URLSessionFetcherTests {
    @Test func theRealFetcherFollowsTheRules() async throws {
        let server = try LocalHTTPServer { req in
            let path = req.line.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
            switch path {
            case "/page":
                return LocalHTTPServer.response(["ETag": "\"v1\"", "Set-Cookie": "session=abc; Path=/", "Last-Modified": "Wed, 22 Oct 2025 10:00:00 GMT"],
                                                body: Data("<p>Hello</p>".utf8))
            case "/cached":
                return req.headers["if-none-match"] == "\"v1\"" ? LocalHTTPServer.response(304, contentType: nil) : LocalHTTPServer.response(body: Data("x".utf8))
            case "/old": return LocalHTTPServer.response(302, ["Location": "/new"], contentType: nil)
            case "/new": return LocalHTTPServer.response(body: Data("arrived".utf8))
            case "/loop": return LocalHTTPServer.response(302, ["Location": "/loop"], contentType: nil)
            case "/big": return LocalHTTPServer.response(body: Data(repeating: UInt8(ascii: "x"), count: 1_000_000))
            case "/image": return LocalHTTPServer.response(body: Data(repeating: 0, count: 500), contentType: "image/png")
            case "/json": return LocalHTTPServer.response(body: Data(#"{"ok":true}"#.utf8), contentType: "application/json")
            case "/login": return LocalHTTPServer.response(401, ["WWW-Authenticate": "Basic realm=\"private\""], body: Data("login".utf8))
            case "/slow":
                Thread.sleep(forTimeInterval: 3)
                return LocalHTTPServer.response()
            default: return LocalHTTPServer.response(404, body: Data("no".utf8))
            }
        }
        defer { server.stop() }
        let fetcher = URLSessionFetcher(policy: URLPolicy(resolver: StubResolver(table: [:])), timeout: 5, maxBytes: 100_000)
        let base = "http://127.0.0.1:\(server.port)"
        func get(_ path: String, _ configure: (inout FetchRequest) -> Void = { _ in }) async throws -> FetchResponse {
            var request = FetchRequest(url: URL(string: base + path)!, allowLocal: true)
            configure(&request)
            return try await fetcher.fetch(request)
        }

        // Without the user's opt-in, this Mac is off limits and nothing is even sent.
        await #expect(throws: URLPolicyError.privateAddress("127.0.0.1")) { try await fetcher.fetch(FetchRequest(url: URL(string: base + "/page")!)) }
        #expect(server.requests.isEmpty)

        // Text comes back whole, with lower-cased headers, and we say who we are but nothing more.
        let page = try await get("/page") { $0.ifNoneMatch = "\"v0\"" }
        #expect(page.status == 200)
        #expect(String(decoding: page.body, as: UTF8.self) == "<p>Hello</p>")
        #expect(page.headers["etag"] == "\"v1\"")
        #expect(page.contentType == "text/html; charset=utf-8")
        #expect(page.finalURL.path == "/page")
        #expect(!page.truncated)
        #expect(server.requests.first?.headers["if-none-match"] == "\"v0\"")
        _ = try await get("/page")
        let second = try #require(server.requests.last)
        #expect(second.headers["cookie"] == nil, "no cookies are kept between requests")
        #expect(second.headers["user-agent"] == "Sidefolk/1.0")
        #expect(second.headers["authorization"] == nil)

        // Validators work: a 304 has no body.
        let cached = try await get("/cached") { $0.ifNoneMatch = "\"v1\"" }
        #expect(cached.status == 304 && cached.body.isEmpty)

        // Redirects are followed, and the end of the road is reported.
        let moved = try await get("/old")
        #expect(moved.status == 200 && moved.finalURL.path == "/new")
        #expect(String(decoding: moved.body, as: UTF8.self) == "arrived")
        // ...but not forever.
        await #expect(throws: URLPolicyError.self) { try await get("/loop") }

        // Big pages are cut at the cap; only text-like content is read.
        let big = try await get("/big")
        #expect(big.truncated && big.body.count == 100_000)
        await #expect(throws: ProbeError.self) { try await get("/image") }
        #expect(try await get("/json").status == 200)

        // Up/down checks stop before the body.
        let headers = try await get("/big") { $0.headersOnly = true }
        #expect(headers.status == 200 && headers.body.isEmpty)
        let head = try await get("/page") { $0.method = "HEAD" }
        #expect(head.status == 200)
        #expect(server.requests.last?.line.hasPrefix("HEAD ") == true)

        // A login prompt is never answered.
        do { #expect(try await get("/login").status == 401) } catch { /* cancelled is fine too */ }
        #expect(server.requests.allSatisfy { $0.headers["authorization"] == nil })

        // A server that stalls is given up on.
        let quick = URLSessionFetcher(policy: URLPolicy(resolver: StubResolver(table: [:])), timeout: 0.5)
        let started = Date()
        await #expect(throws: URLError.self) { try await quick.fetch(FetchRequest(url: URL(string: base + "/slow")!, allowLocal: true)) }
        #expect(Date().timeIntervalSince(started) < 2.5)
    }
}
