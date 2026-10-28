import Foundation
import Security

/// Who signed a copy of Sidefolk, as macOS reads it from the signature (D46). Read from the running app,
/// never written into the code: a fork signed by someone else updates only from its own developer.
public struct SigningFacts: Sendable, Equatable {
    public var teamID: String?
    /// The code-signing identifier (the bundle id for the app).
    public var identifier: String?
    public var adHoc: Bool
    /// Signed with a Developer ID Application certificate, the kind notarized apps outside the App Store carry.
    public var developerID: Bool

    public init(teamID: String?, identifier: String?, adHoc: Bool, developerID: Bool) {
        self.teamID = teamID
        self.identifier = identifier
        self.adHoc = adHoc
        self.developerID = developerID
    }

    /// From `SecCodeCopySigningInformation`'s dictionary; `leafName` is the first certificate's summary
    /// ("Developer ID Application: Name (TEAMID)"), read from its certificates unless given.
    public init(info: [String: Any], leafName: String? = nil) {
        teamID = info[kSecCodeInfoTeamIdentifier as String] as? String
        identifier = info[kSecCodeInfoIdentifier as String] as? String
        let flags = (info[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        adHoc = flags & SecCodeSignatureFlags.adhoc.rawValue != 0
        let leaf = leafName ?? (info[kSecCodeInfoCertificates as String] as? [SecCertificate])?.first
            .flatMap { SecCertificateCopySubjectSummary($0) as String? }
        developerID = !adHoc && leaf?.hasPrefix("Developer ID Application:") == true
    }

    /// The copy at `url` (an app bundle or a disk image); nil when it carries no signature at all.
    public static func of(_ url: URL) -> SigningFacts? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        return of(code)
    }

    public static func ofRunningApp() -> SigningFacts? {
        var running: SecCode?
        var code: SecStaticCode?
        guard SecCodeCopySelf([], &running) == errSecSuccess, let running,
              SecCodeCopyStaticCode(running, [], &code) == errSecSuccess, let code else { return nil }
        return of(code)
    }

    private static func of(_ code: SecStaticCode) -> SigningFacts? {
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any], dict[kSecCodeInfoIdentifier as String] != nil else { return nil }
        return SigningFacts(info: dict)
    }

    /// What a replacement must be: anchored at Apple, signed with a Developer ID certificate of this team, with
    /// this identifier, and notarized. nil when this copy isn't a Developer ID one (it then never replaces itself).
    public var replacementRequirement: String? {
        guard developerID, let team = teamID, let id = identifier,
              team.range(of: #"^[A-Z0-9]{10}$"#, options: .regularExpression) != nil,
              id.range(of: #"^[A-Za-z0-9.\-]+$"#, options: .regularExpression) != nil else { return nil }
        // 6.1.13: a Developer ID Application leaf; 6.2.6: issued by the Developer ID intermediate.
        return "anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] and "
            + "certificate 1[field.1.2.840.113635.100.6.2.6] and certificate leaf[subject.OU] = \"\(team)\" and "
            + "identifier \"\(id)\" and notarized"
    }
}

/// Checks a copy's signature: every file intact (nested code too), strictly, for every architecture, and meeting
/// `requirement`. Throws a sentence a person can read.
public protocol CodeChecking: Sendable {
    func check(_ url: URL, requirement: String) throws
}

public struct CodeCheck: CodeChecking {
    public init() {}

    public func check(_ url: URL, requirement: String) throws {
        var code: SecStaticCode?
        var req: SecRequirement?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(requirement as CFString, [], &req) == errSecSuccess, let req else {
            throw UserFacingError("The new version carries no signature Sidefolk can read, so it wasn't installed.")
        }
        var error: Unmanaged<CFError>?
        let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)
        let status = SecStaticCodeCheckValidityWithErrors(code, flags, req, &error)
        guard status == errSecSuccess else {
            let detail = (error?.takeRetainedValue()).map { CFErrorCopyDescription($0) as String } ?? "OSStatus \(status)"
            throw status == errSecCSReqFailed
                ? UserFacingError("The new version isn't signed and notarized by Sidefolk's developer, so it wasn't installed.",
                                  detail: detail)
                : UserFacingError("The new version's signature doesn't check out, so it wasn't installed.", detail: detail)
        }
    }
}
