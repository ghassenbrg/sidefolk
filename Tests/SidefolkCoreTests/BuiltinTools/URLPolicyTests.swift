import Foundation
import Synchronization
import Testing
@testable import SidefolkCore

/// Answers DNS from a table instead of the network.
struct StubResolver: HostResolving {
    var table: [String: [IPAddress]]
    func addresses(for host: String) async throws -> [IPAddress] {
        guard let found = table[host] else { throw URLPolicy.Violation.cannotResolve(host) }
        return found
    }
}

private func ip(_ text: String) -> IPAddress { IPAddress.parse(text)! }

@Suite struct URLPolicyTests {
    @Test func syntaxAcceptsOnlyPlainWebAddresses() throws {
        #expect(try URLPolicy.parseWebURL(" https://example.com/a?b=1#c ").absoluteString == "https://example.com/a?b=1#c")
        #expect(try URLPolicy.parseWebURL("HTTP://Example.com").host == "Example.com")

        let schemes = ["file:///etc/passwd", "javascript:alert(1)", "data:text/plain,hi", "blob:https://x/y", "about:blank", "ftp://example.com",
                       "ssh://host", "mailto:a@b.com", "shortcuts://run-shortcut", "vscode://file/x"]
        for text in schemes {
            #expect(throws: URLPolicy.Violation.self, "should refuse \(text)") { try URLPolicy.parseWebURL(text) }
        }
        for text in ["", "example.com", "//example.com", "https://", "https://exa mple.com", "https://example.com/\nGET /x",
                     "https://user:pass@example.com/", "https://user@example.com/", "https://" + String(repeating: "a", count: 2_100) + ".com"] {
            #expect(throws: URLPolicy.Violation.self, "should refuse \(text.prefix(40))") { try URLPolicy.parseWebURL(text) }
        }
    }

    @Test func hostsThatMeanThisMachineOrNetworkAreRefused() throws {
        let blocked = [
            "http://localhost/", "http://LOCALHOST./", "http://app.localhost/", "http://printer.local/", "http://intranet/",
            "http://nas.internal/", "http://router.home.arpa/",
            "http://127.0.0.1/", "http://127.0.0.2:8080/", "http://0.0.0.0/", "http://10.1.2.3/", "http://172.16.0.1/", "http://172.31.255.255/",
            "http://192.168.1.1/", "http://169.254.169.254/latest/meta-data", "http://100.64.0.1/", "http://198.18.0.1/", "http://192.0.0.8/",
            "http://224.0.0.1/", "http://240.0.0.1/", "http://255.255.255.255/", "http://198.51.100.7/", "http://203.0.113.7/",
            "http://[::1]/", "http://[::]/", "http://[::ffff:127.0.0.1]/", "http://[::ffff:10.0.0.1]/", "http://[fe80::1]/", "http://[fc00::1]/",
            "http://[fd12:3456::1]/", "http://[ff02::1]/", "http://[64:ff9b::7f00:1]/", "http://[2002:7f00:1::1]/", "http://[2001:db8::1]/",
        ]
        for text in blocked {
            let url = try URLPolicy.parseWebURL(text)
            #expect(throws: URLPolicy.Violation.self, "should block \(text)") { try URLPolicy.checkHost(url) }
        }
    }

    @Test func unusualIPSpellingsAreRefusedBecauseSystemsReadThemDifferently() throws {
        for text in ["http://127.1/", "http://2130706433/", "http://0x7f.1/", "http://0177.0.0.1/", "http://0x7f000001/", "http://1.2.3/",
                     "http://127.0.0.1.", "http://127.0.0.1%2e/", "http://017700000001/"] {
            let url = try URLPolicy.parseWebURL(text)
            #expect(throws: URLPolicy.Violation.self, "should refuse \(text)") { try URLPolicy.checkHost(url) }
        }
    }

    @Test func publicHostsPass() throws {
        for text in ["https://example.com/", "https://sub.example.co.uk/x", "http://93.184.216.34/", "https://[2606:4700:4700::1111]/",
                     "https://xn--bcher-kva.de/", "https://bücher.de/", "http://8.8.8.8:8080/"] {
            let url = try URLPolicy.parseWebURL(text)
            try URLPolicy.checkHost(url)
        }
    }

    @Test func ipClassification() {
        #expect(ip("93.184.216.34").isPublic)
        #expect(ip("1.1.1.1").isPublic)
        #expect(ip("172.32.0.1").isPublic)       // just outside 172.16/12
        #expect(ip("100.128.0.1").isPublic)      // just outside 100.64/10
        #expect(!ip("172.16.5.5").isPublic)
        #expect(!ip("100.127.255.255").isPublic)
        #expect(ip("2606:4700:4700::1111").isPublic)
        #expect(!ip("::ffff:192.168.0.1").isPublic)
        #expect(ip("::ffff:8.8.8.8").isPublic)
        #expect(IPAddress.parse("127.1") == nil)
        #expect(IPAddress.parse("01.2.3.4") == nil)
        #expect(IPAddress.parse("256.1.1.1") == nil)
    }

    @Test func namesThatResolveToPrivateAddressesAreRefused() async throws {
        let resolver = StubResolver(table: [
            "ok.test": [ip("93.184.216.34")],
            "mixed.test": [ip("93.184.216.34"), ip("10.0.0.5")],
            "rebind.test": [ip("127.0.0.1")],
            "v6.test": [ip("::1")],
            "empty.test": [],
        ])
        let policy = URLPolicy(resolver: resolver)
        try await policy.validate("https://ok.test/page")
        for text in ["https://mixed.test/", "https://rebind.test/", "https://v6.test/"] {
            await #expect(throws: URLPolicy.Violation.self, "should refuse \(text)") { try await policy.validate(text) }
        }
        await #expect(throws: URLPolicy.Violation.cannotResolve("empty.test")) { try await policy.validate("https://empty.test/") }
        await #expect(throws: URLPolicy.Violation.cannotResolve("nx.test")) { try await policy.validate("https://nx.test/") }

        // Only the UI path for a user-typed destination may allow private hosts.
        let permissive = URLPolicy(resolver: resolver, allowPrivate: true)
        try await permissive.validate("http://localhost:3000/")
        try await permissive.validate("https://rebind.test/")
        await #expect(throws: URLPolicy.Violation.self) { try await permissive.validate("ftp://localhost/") }
    }

    @Test func theRealAddressOfAConnectionIsChecked() throws {
        let policy = URLPolicy()
        try policy.checkRemoteAddress("93.184.216.34")
        for text in ["127.0.0.1", "10.0.0.8", "::1", "fe80::1%en0", "garbage"] {
            #expect(throws: URLPolicy.Violation.self, "should refuse \(text)") { try policy.checkRemoteAddress(text) }
        }
    }

    @Test func systemResolverResolvesNumericAndLocalNames() async throws {
        let resolver = SystemHostResolver()
        let local = try await resolver.addresses(for: "localhost")
        #expect(local.contains { !$0.isPublic })
        await #expect(throws: URLPolicy.Violation.self) { _ = try await resolver.addresses(for: "this-host-does-not-exist.invalid") }
    }
}
