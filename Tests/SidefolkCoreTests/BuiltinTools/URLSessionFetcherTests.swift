import Foundation
import Synchronization
import Testing
@testable import SidefolkCore

/// Stands in for the network: each URL maps to a canned answer. URLs are unique per test, so the
/// shared table is safe while tests run in parallel.
final class StubNetworkProtocol: URLProtocol, @unchecked Sendable {
    enum Answer {
        case page(status: Int = 200, type: String?, body: Data)
        case redirect(to: String)
    }
    private static let answers = Mutex<[String: Answer]>([:])
    private static let hits = Mutex<[String]>([])

    static func set(_ url: String, _ answer: Answer) { answers.withLock { $0[url] = answer } }
    static func requests(for prefix: String) -> [String] { hits.withLock { $0.filter { $0.hasPrefix(prefix) } } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url else { return }
        Self.hits.withLock { $0.append(url.absoluteString) }
        guard let answer = Self.answers.withLock({ $0[url.absoluteString] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        switch answer {
        case .redirect(let target):
            let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": target])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: URL(string: target)!), redirectResponse: response)
        case .page(let status, let type, let body):
            var headers: [String: String] = [:]
            if let type { headers["Content-Type"] = type }
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
}

private func fetcher(_ names: [String: [IPAddress]] = [:]) -> URLSessionFetcher {
    var table = names
    for host in ["a.test", "b.test", "c.test", "d.test", "e.test", "f.test", "g.test", "h.test", "i.test", "j.test"] where table[host] == nil {
        table[host] = [IPAddress.parse("93.184.216.34")!]
    }
    return URLSessionFetcher(policy: URLPolicy(resolver: StubHostResolver(table: table)), protocolClasses: [StubNetworkProtocol.self])
}

private func page(_ text: String, type: String? = "text/html; charset=utf-8") -> StubNetworkProtocol.Answer { .page(type: type, body: Data(text.utf8)) }

@Suite struct URLSessionFetcherTests {
    @Test func fetchesAPage() async throws {
        StubNetworkProtocol.set("https://a.test/hello", page("<html><title>Hi</title></html>"))
        let response = try await fetcher().get(URL(string: "https://a.test/hello")!, options: WebFetchOptions())
        #expect(response.statusCode == 200)
        #expect(response.contentType == "text/html; charset=utf-8")
        #expect(String(decoding: response.body, as: UTF8.self).contains("<title>Hi</title>"))
        #expect(response.url.absoluteString == "https://a.test/hello")
        #expect(!response.truncated)
    }

    @Test func followsPublicRedirectsAndReportsTheFinalURL() async throws {
        StubNetworkProtocol.set("https://b.test/start", .redirect(to: "https://b.test/middle"))
        StubNetworkProtocol.set("https://b.test/middle", .redirect(to: "https://c.test/end"))
        StubNetworkProtocol.set("https://c.test/end", page("arrived"))
        let response = try await fetcher().get(URL(string: "https://b.test/start")!, options: WebFetchOptions())
        #expect(response.url.absoluteString == "https://c.test/end")
        #expect(response.requestedURL.absoluteString == "https://b.test/start")
        #expect(String(decoding: response.body, as: UTF8.self) == "arrived")
    }

    @Test func aRedirectToAPrivateHostIsRefusedBeforeItIsFollowed() async throws {
        StubNetworkProtocol.set("https://d.test/bounce", .redirect(to: "http://169.254.169.254/latest/meta-data"))
        StubNetworkProtocol.set("https://d.test/bounce2", .redirect(to: "https://rebind.test/x"))
        StubNetworkProtocol.set("https://rebind.test/x", page("secret"))
        let f = fetcher(["rebind.test": [IPAddress.parse("127.0.0.1")!]])
        await #expect(throws: WebFetchError.self) { _ = try await f.get(URL(string: "https://d.test/bounce")!, options: WebFetchOptions()) }
        await #expect(throws: WebFetchError.self) { _ = try await f.get(URL(string: "https://d.test/bounce2")!, options: WebFetchOptions()) }
        #expect(StubNetworkProtocol.requests(for: "http://169.254").isEmpty)
        #expect(StubNetworkProtocol.requests(for: "https://rebind.test").isEmpty)
    }

    @Test func aFirstHopToAPrivateHostNeverSendsARequest() async throws {
        StubNetworkProtocol.set("http://127.0.0.1/admin", page("admin"))
        StubNetworkProtocol.set("https://e.test/x", page("fine"))
        let f = fetcher()
        do {
            _ = try await f.get(URL(string: "http://127.0.0.1/admin")!, options: WebFetchOptions())
            Issue.record("expected a refusal")
        } catch let error as WebFetchError {
            guard case .blocked(.privateDestination) = error else { Issue.record("wrong error \(error)"); return }
        }
        #expect(StubNetworkProtocol.requests(for: "http://127.0.0.1").isEmpty)
    }

    @Test func secureToInsecureRedirectsAreRefused() async throws {
        StubNetworkProtocol.set("https://f.test/down", .redirect(to: "http://f.test/plain"))
        StubNetworkProtocol.set("http://f.test/plain", page("insecure"))
        do {
            _ = try await fetcher().get(URL(string: "https://f.test/down")!, options: WebFetchOptions())
            Issue.record("expected a refusal")
        } catch let error as WebFetchError {
            #expect(error == .blocked(.insecureRedirect))
        }
        #expect(StubNetworkProtocol.requests(for: "http://f.test").isEmpty)
    }

    @Test func redirectLoopsStopAtFive() async throws {
        for i in 0..<8 { StubNetworkProtocol.set("https://g.test/\(i)", .redirect(to: "https://g.test/\(i + 1)")) }
        do {
            _ = try await fetcher().get(URL(string: "https://g.test/0")!, options: WebFetchOptions())
            Issue.record("expected a refusal")
        } catch let error as WebFetchError {
            #expect(error == .blocked(.tooManyRedirects))
        }
        #expect(StubNetworkProtocol.requests(for: "https://g.test/").count <= 6)
    }

    @Test func largeBodiesAreCutAtTheLimit() async throws {
        StubNetworkProtocol.set("https://h.test/big", page(String(repeating: "x", count: 50_000), type: "text/plain"))
        var options = WebFetchOptions()
        options.maxBytes = 1_000
        let response = try await fetcher().get(URL(string: "https://h.test/big")!, options: options)
        #expect(response.body.count == 1_000)
        #expect(response.truncated)
    }

    @Test func nonTextContentIsRefusedWithoutDownloadingIt() async throws {
        StubNetworkProtocol.set("https://i.test/pic", .page(type: "image/png", body: Data(repeating: 1, count: 100)))
        do {
            _ = try await fetcher().get(URL(string: "https://i.test/pic")!, options: WebFetchOptions())
            Issue.record("expected a refusal")
        } catch let error as WebFetchError {
            #expect(error == .unsupportedType("image/png"))
        }
    }

    @Test func unreachableSitesAreReportedAsNetworkErrors() async throws {
        do {
            _ = try await fetcher().get(URL(string: "https://j.test/unknown")!, options: WebFetchOptions())
            Issue.record("expected an error")
        } catch let error as WebFetchError {
            guard case .network = error else { Issue.record("wrong error \(error)"); return }
        }
    }
}
