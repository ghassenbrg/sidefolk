import Testing
@testable import SidefolkCore

@Suite struct RedactorTests {
    /// The word after "Authorization:" is usually its scheme, and the secret comes after that.
    @Test func aSchemeIsntTheSecret() {
        for scheme in ["Bearer", "bearer", "Basic", "Token"] {
            let redacted = Redactor.redact("Authorization: \(scheme) canary0123456789")
            #expect(!redacted.contains("canary"), "\(redacted)")
            #expect(redacted.hasPrefix("Authorization: \(scheme)"), "\(redacted)")
        }
        #expect(!Redactor.redact("Authorization: Bearer canary").contains("canary"))
        #expect(Redactor.redact("password: hunter2-canary") == "password: [redacted]")
        #expect(Redactor.redact("the token was lost") == "the token was lost")
    }
}
