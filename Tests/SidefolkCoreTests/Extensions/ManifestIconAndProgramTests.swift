import CoreGraphics
import Darwin
import Foundation
import Testing
@testable import SidefolkCore

/// The manifest fields added for D39: `icon`, programs named without a path, and `tools.<name>.paths`
/// and `timeout`. Nothing here runs an extension.
@Suite final class ManifestIconAndProgramTests {
    let root: URL
    let paths: SidefolkPaths
    /// "git" found at /usr/sbin/sysctl: a real root-owned binary under a prefix (/usr), so no developer tools are needed.
    static let programs = ProgramResolver { $0 == "git" ? ["/usr/sbin/sysctl"] : [] }

    init() throws {
        root = try ExtFixtures.tempDir("icons")
        paths = SidefolkPaths(home: root.appendingPathComponent("home", isDirectory: true))
    }

    deinit { ExtensionFiles.removeTree(root.path) }

    func validate(_ manifest: JSONValue, folder: String, files: [String: Data] = [:], programs: ProgramResolver = programs) throws -> ValidationReport {
        let dir = try ExtFixtures.makeExtension(at: root.appendingPathComponent(folder, isDirectory: true), manifest: manifest,
                                                files: ["server.py": "print()"])
        for (path, data) in files { try data.write(to: dir.appendingPathComponent(path)) }
        return ManifestValidator(paths: paths, resolver: ManifestValidationTests.resolver, programs: programs).validate(folder: dir)
    }

    /// The first 24 bytes of a PNG: signature, then the IHDR chunk with width and height (enough for the check).
    static func png(width: UInt32, height: UInt32, padding: Int = 0) -> Data {
        var d = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13]) + Data("IHDR".utf8)
        for v in [width, height] { d += Data([UInt8(v >> 24), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)]) }
        return d + Data([8, 6, 0, 0, 0]) + Data(repeating: 0, count: padding)
    }

    static func pdf(width: CGFloat, height: CGFloat, pages: Int = 1) -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: width, height: height)
        let context = CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: &box, nil)!
        for _ in 0..<pages {
            context.beginPDFPage(nil)
            context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    @Test func iconsArePNGsOrPDFsCheckedAsImages() throws {
        let ok = try validate(ExtFixtures.manifest(extra: ["icon": "icon.png"]), folder: "a", files: ["icon.png": Self.png(width: 512, height: 512)])
        #expect(ok.isValid, "\(ok.errors)")
        #expect(ok.iconPath?.hasSuffix("/a/icon.png") == true)
        #expect(ok.text.contains("Icon: icon.png"))
        let missing = try validate(ExtFixtures.manifest(extra: ["icon": "art/icon.pdf"]), folder: "b",
                                  files: [:])
        #expect(missing.errors.map(\.field) == ["icon"], "a missing file is named")

        let cases: [(String, String, Data, String)] = [
            ("c", "icon.png", Self.png(width: 512, height: 256), "must be square"),
            ("d", "icon.png", Self.png(width: 32, height: 32), "between 64 and 1024"),
            ("e", "icon.png", Data("<svg/>".utf8), "isn't a PNG"),
            ("f", "icon.svg", Data("<svg/>".utf8), "SVG isn't accepted"),
            ("g", "icon.png", Self.png(width: 512, height: 512, padding: 300 * 1024), "256 KiB"),
            ("h", "icon.pdf", Self.pdf(width: 512, height: 512, pages: 2), "exactly one page"),
            ("i", "icon.pdf", Self.pdf(width: 512, height: 300), "must be square"),
            ("j", "icon.pdf", Data("%PDF-1.4 nothing".utf8), "isn't a PDF"),
        ]
        for (folder, name, data, message) in cases {
            let r = try validate(ExtFixtures.manifest(extra: ["icon": .string(name)]), folder: folder, files: [name: data])
            #expect(r.errors.first?.field == "icon", "\(folder)")
            #expect(r.errors.first?.message.contains(message) == true, "\(folder): \(r.errors)")
            #expect(r.iconPath == nil)
        }
        let square = try validate(ExtFixtures.manifest(extra: ["icon": "icon.pdf"]), folder: "k", files: ["icon.pdf": Self.pdf(width: 512, height: 512)])
        #expect(square.isValid, "\(square.errors)")
    }

    @Test func iconsCantBeLinksOrLeaveTheFolder() throws {
        let outside = root.appendingPathComponent("elsewhere.png")
        try Self.png(width: 512, height: 512).write(to: outside)
        let dir = try ExtFixtures.makeExtension(at: root.appendingPathComponent("link", isDirectory: true),
                                                manifest: ExtFixtures.manifest(extra: ["icon": "icon.png"]), files: ["server.py": "print()"])
        try FileManager.default.createSymbolicLink(atPath: dir.appendingPathComponent("icon.png").path, withDestinationPath: outside.path)
        let r = ManifestValidator(paths: paths, resolver: ManifestValidationTests.resolver, programs: Self.programs).validate(folder: dir)
        #expect(r.errors.first?.field == "icon")
        let escape = try validate(ExtFixtures.manifest(extra: ["icon": "../elsewhere.png"]), folder: "escape")
        #expect(escape.errors.first?.field == "icon")
    }

    @Test func shippedIconsPassTheChecks() {
        for folder in ExtFixtures.builtInFolders.map(ExtFixtures.builtIn) + [ExtFixtures.repoRoot.appendingPathComponent("extensions/hello-folk")] {
            let name = folder.lastPathComponent
            let r = ManifestValidator(paths: paths, resolver: ManifestValidationTests.resolver, programs: Self.programs).validate(folder: folder)
            #expect(r.isValid, "\(name): \(r.errors)")
            #expect(r.iconPath != nil, "\(name)")
        }
    }

    @Test func programsNamedWithoutAPathAreFoundAndPinned() throws {
        let r = try validate(ExtFixtures.manifest(permissions: ["exec": ["git"]]), folder: "prog")
        #expect(r.isValid, "\(r.errors)")
        #expect(r.permissions?.exec == [])
        #expect(r.permissions?.programs.map(\.name) == ["git"])
        #expect(r.permissions?.programs.first?.path == "/usr/sbin/sysctl")
        #expect(r.permissions?.programs.first?.environmentKey == "SIDEFOLK_EXEC_GIT")
        // A named program is not "can run anything": the sandbox lets it start only its own helpers.
        #expect(r.permissions?.dangerousExec == [])
        #expect(r.summary?.texts == ["Can run git (/usr/sbin/sysctl)", "No access to your files or the internet"])

        let missing = try validate(ExtFixtures.manifest(permissions: ["exec": ["git"]]), folder: "noprog",
                                   programs: ProgramResolver { _ in [] })
        #expect(missing.errors.first?.field == "permissions.exec[0]")
        #expect(missing.errors.first?.message.contains("xcode-select --install") == true)

        let unknown = try validate(ExtFixtures.manifest(permissions: ["exec": ["ffmpeg-ish"]]), folder: "unknown")
        #expect(unknown.errors.first?.message.contains("absolute path") == true)
        #expect(unknown.errors.first?.message.contains("git") == true, "the message says which names work")
    }

    @Test func systemGitResolvesToTheRealBinaryNotTheShim() throws {
        guard let git = ProgramResolver.system.resolve("git") else { return } // no developer tools or Homebrew git here
        #expect(!git.path.hasPrefix("/usr/bin/"))
        #expect(git.helpers.contains { $0.hasSuffix("/git-remote-http") })
        #expect(!git.runtime.isEmpty)
    }

    @Test func folderParametersAndTimeoutsAreChecked() throws {
        let ok = try validate(ExtFixtures.manifest(tools: ["echo": ["risk": "low", "paths": ["into": "write", "from": "read"], "timeout": 120]]),
                              folder: "params")
        #expect(ok.isValid, "\(ok.errors)")
        #expect(ok.permissions?.folders == .write)
        // Writing in a folder named per call raises every tool to medium, like a manifest folder would.
        #expect(ok.toolRisks.map(\.risk) == [.medium])
        #expect(ok.summary?.texts.first?.contains("a folder you name") == true)

        let read = try validate(ExtFixtures.manifest(tools: ["echo": ["risk": "low", "paths": ["from": "read"]]]), folder: "readonly")
        #expect(read.permissions?.folders == .read)
        #expect(read.toolRisks.map(\.risk) == [.low])

        let bad = try validate(ExtFixtures.manifest(tools: ["echo": ["paths": ["Bad-Name": "read"], "timeout": 900]]), folder: "badparams")
        #expect(Set(bad.errors.map(\.field)) == ["tools.echo.timeout", "tools.echo.paths.Bad-Name"])
        let kind = try validate(ExtFixtures.manifest(tools: ["echo": ["paths": ["into": "delete"]]]), folder: "badkind")
        #expect(kind.errors.first?.field.hasPrefix("tools.echo.paths") == true)
    }

    @Test func networkAndFoldersNamedPerCallAreWarnedAbout() {
        let summary = PermissionSummary.forExtension(ExtensionPermissions(network: true, folders: .write))
        #expect(summary.texts == ["Can use the internet",
                                  "Can read and change files in a folder you name, for that request only, once you approve it"])
        #expect(summary.warnings.contains { $0.contains("upload what's in that folder") })
    }

    @Test func pinsSavedBeforeProgramsStillDecode() throws {
        let old = try JSONValue.parse(#"{"network":false,"read":[],"write":[],"exec":["/usr/bin/pmset"]}"#)
        let decoded = try old.decode(ExtensionPermissions.self)
        #expect(decoded.exec == ["/usr/bin/pmset"])
        #expect(decoded.programs.isEmpty)
        #expect(decoded.folders == nil)
    }
}
