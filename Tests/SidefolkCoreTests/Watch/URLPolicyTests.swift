import Foundation
import Testing
@testable import SidefolkCore

@Suite struct URLPolicyTests {
    let publicV4 = IPAddress.parse("93.184.216.34")!

    func syntaxError(_ text: String, allowLocal: Bool = false) -> URLPolicyError? {
        guard let url = URL(string: text) else { return .noHost }
        do { try URLPolicy.checkSyntax(url, allowLocal: allowLocal); return nil } catch { return error as? URLPolicyError }
    }

    func policy(_ table: [String: [IPAddress]] = [:]) -> URLPolicy { URLPolicy(resolver: StubResolver(table: table)) }

    @Test func onlyHttpAndHttpsAreWatched() {
        for text in ["ftp://example.com/x", "file:///etc/passwd", "javascript:alert(1)", "data:text/plain,hi", "mailto:a@b.c", "ssh://example.com"] {
            #expect(syntaxError(text) == .notWeb, "\(text)")
        }
        #expect(syntaxError("https://example.com/pricing") == nil)
        #expect(syntaxError("HTTP://Example.com") == nil)
    }

    @Test func addressesWithLoginsAreRefused() {
        #expect(syntaxError("https://user:secret@example.com/") == .credentials)
        #expect(syntaxError("https://user@example.com/") == .credentials)
        #expect(syntaxError("https://@example.com/") == .credentials)
    }

    @Test func tooLongAddressesAreRefused() {
        #expect(syntaxError("https://example.com/" + String(repeating: "a", count: URLPolicy.maxLength)) == .tooLong)
    }

    @Test func loopbackPrivateAndLinkLocalLiteralsAreRefusedInEveryDisguise() {
        let blocked = [
            "http://127.0.0.1/", "http://127.1/", "http://2130706433/", "http://0177.0.0.1/", "http://0x7f.1/", "http://127.255.255.254/",
            "http://[::1]/", "http://[::ffff:127.0.0.1]/", "http://[::ffff:10.0.0.1]/", "http://[::]/", "http://0.0.0.0/",
            "http://169.254.169.254/latest/meta-data/", "http://169.254.0.1/",
            "http://10.0.0.5/", "http://172.16.0.1/", "http://172.31.255.255/", "http://192.168.1.1/", "http://192.168.255.255:8080/",
            "http://100.64.0.1/", "http://100.127.255.255/", "http://192.0.0.8/", "http://198.18.0.1/", "http://198.19.255.255/",
            "http://224.0.0.1/", "http://239.255.255.250/", "http://240.0.0.1/", "http://255.255.255.255/",
            "http://[fe80::1]/", "http://[fd00::1]/", "http://[fc00::1234]/", "http://[ff02::1]/",
            "http://[64:ff9b::7f00:1]/", "http://[2002:7f00:1::]/",
        ]
        for text in blocked {
            guard let error = syntaxError(text) else { Issue.record("\(text) should be refused"); continue }
            if case .privateAddress = error {} else { Issue.record("\(text): unexpected \(error)") }
        }
    }

    @Test func publicLiteralsPass() {
        for text in ["http://93.184.216.34/", "http://172.32.0.1/", "http://172.15.255.255/", "http://100.128.0.1/", "http://100.63.255.255/",
                     "http://198.20.0.1/", "http://[2606:2800:220:1:248:1893:25c8:1946]/", "http://[64:ff9b::5db8:d822]/"] {
            #expect(syntaxError(text) == nil, "\(text)")
        }
    }

    @Test func localNamesAreRefused() {
        for text in ["http://localhost:3000/", "http://LOCALHOST/", "http://localhost./", "http://app.localhost/", "http://printer.local/",
                     "http://intranet/", "http://nas/share"] {
            guard let error = syntaxError(text) else { Issue.record("\(text) should be refused"); continue }
            if case .localName = error {} else { Issue.record("\(text): unexpected \(error)") }
        }
        #expect(syntaxError("https://example.com") == nil)
        #expect(syntaxError("https://sub.example.co.uk") == nil)
    }

    @Test func theUserCanOptIntoLocalTargets() {
        #expect(syntaxError("http://localhost:3000/", allowLocal: true) == nil)
        #expect(syntaxError("http://192.168.1.20/", allowLocal: true) == nil)
        // Opting in does not relax the rest.
        #expect(syntaxError("ftp://localhost/", allowLocal: true) == .notWeb)
        #expect(syntaxError("http://me:pw@localhost/", allowLocal: true) == .credentials)
    }

    @Test func aNameThatResolvesToAPrivateAddressIsRefused() async throws {
        let p = policy([
            "good.example": [publicV4],
            "evil.example": [IPAddress.parse("10.1.2.3")!],
            "mixed.example": [publicV4, IPAddress.parse("192.168.0.9")!],
            "rebind.example": [publicV4, IPAddress.parse("::1")!],
            "nip.example": [IPAddress.parse("127.0.0.1")!],
        ])
        try await p.validate(URL(string: "https://good.example/")!, allowLocal: false)
        for host in ["evil", "mixed", "rebind", "nip"] {
            await #expect(throws: URLPolicyError.privateAddress("\(host).example")) {
                try await p.validate(URL(string: "https://\(host).example/")!, allowLocal: false)
            }
        }
        await #expect(throws: URLPolicyError.unresolvable("nowhere.example")) {
            try await p.validate(URL(string: "https://nowhere.example/")!, allowLocal: false)
        }
    }

    @Test func allowLocalSkipsTheAddressChecksOnly() async throws {
        let p = policy(["evil.example": [IPAddress.parse("10.1.2.3")!]])
        try await p.validate(URL(string: "https://evil.example/")!, allowLocal: true)
        await #expect(throws: URLPolicyError.notWeb) { try await p.validate(URL(string: "file:///etc/hosts")!, allowLocal: true) }
    }

    @Test func redirectsAreCheckedLikeTheFirstRequest() async throws {
        let p = policy(["good.example": [publicV4], "other.example": [publicV4], "evil.example": [IPAddress.parse("169.254.169.254")!]])
        let from = URL(string: "https://good.example/a")!
        try await p.checkRedirect(from: from, to: URL(string: "https://other.example/b")!, hop: 1, allowLocal: false)
        // Down to http is allowed from http, never from https.
        try await p.checkRedirect(from: URL(string: "http://good.example/")!, to: URL(string: "https://other.example/")!, hop: 1, allowLocal: false)
        await #expect(throws: URLPolicyError.self) {
            try await p.checkRedirect(from: from, to: URL(string: "http://other.example/")!, hop: 1, allowLocal: false)
        }
        await #expect(throws: URLPolicyError.privateAddress("evil.example")) {
            try await p.checkRedirect(from: from, to: URL(string: "https://evil.example/")!, hop: 1, allowLocal: false)
        }
        await #expect(throws: URLPolicyError.self) {
            try await p.checkRedirect(from: from, to: URL(string: "http://127.0.0.1/admin")!, hop: 2, allowLocal: false)
        }
        await #expect(throws: URLPolicyError.self) {
            try await p.checkRedirect(from: from, to: URL(string: "https://other.example/")!, hop: URLPolicy.maxRedirects + 1, allowLocal: false)
        }
    }

    @Test func systemResolverHandlesNumericFormsWithoutTheNetwork() async throws {
        // getaddrinfo normalises odd spellings of numeric hosts without asking DNS.
        for host in ["127.1", "2130706433", "0x7f.1", "::1"] {
            let found = try await SystemResolver(timeout: 5).resolve(host)
            #expect(found.allSatisfy(URLPolicy.isBlocked), "\(host)")
        }
    }

    @Test func ipv6ParsingKeepsBracketsAndZonesOut() {
        #expect(IPAddress.parse("[::1]") == IPAddress.parse("::1"))
        #expect(IPAddress.parse("fe80::1%en0") == IPAddress.parse("fe80::1"))
        #expect(IPAddress.parse("1.2.3.4 foo") == nil)
        #expect(IPAddress.parse("example.com") == nil)
    }

    @Test func eachHostGetsOneRequestAMinute() {
        let throttle = HostThrottle()
        let t0 = TestEnv.referenceDate
        #expect(throttle.reserve(host: "a.example", now: t0) == nil)
        #expect(throttle.reserve(host: "b.example", now: t0) == nil)
        #expect(throttle.reserve(host: "a.example", now: t0.addingTimeInterval(20)) == t0.addingTimeInterval(60))
        // A watcher on a 60 s interval is not pushed back by a little scheduling jitter.
        #expect(throttle.reserve(host: "a.example", now: t0.addingTimeInterval(59)) == nil)
        #expect(throttle.reserve(host: "a.example", now: t0.addingTimeInterval(59.5)) != nil)
    }
}
