import Darwin
import Foundation
import Testing
@testable import SidefolkCore

/// SECURITY T13 and §4.5: every manifest rule, without running anything.
@Suite final class ManifestValidationTests {
    let root: URL
    let paths: SidefolkPaths
    /// Finds "python3" at /bin/sh: a real, root-owned binary, so these tests don't depend on Python.
    static let resolver = InterpreterResolver { name in ["python3", "sh", "node"].contains(name) ? ["/bin/sh"] : [] }

    init() throws {
        root = try ExtFixtures.tempDir("manifest")
        paths = SidefolkPaths(home: root.appendingPathComponent("home", isDirectory: true))
    }

    deinit { ExtensionFiles.removeTree(root.path) }

    func validate(_ manifest: JSONValue, folder: String = "dev.test.sample", files: [String: String] = ["server.py": "print()"],
                  mode: ManifestValidator.Mode = .source) throws -> ValidationReport {
        let dir = try ExtFixtures.makeExtension(at: root.appendingPathComponent(folder, isDirectory: true), manifest: manifest, files: files)
        return ManifestValidator(paths: paths, resolver: Self.resolver).validate(folder: dir, mode: mode)
    }

    func fields(_ r: ValidationReport) -> [String] { r.errors.map(\.field) }

    @Test func shippedExtensionsAndTheSampleAreValid() {
        let folders = (ExtFixtures.builtInFolders + ExtFixtures.addonFolders).map(ExtFixtures.builtIn) + [ExtFixtures.repoRoot.appendingPathComponent("extensions/hello-folk")]
        for folder in folders {
            let r = ExtensionValidator.validate(at: folder, paths: paths, resolver: Self.resolver)
            #expect(r.isValid, "\(folder.lastPathComponent): \(r.errors)")
            #expect(r.warnings.isEmpty, "\(folder.lastPathComponent): \(r.warnings)")
        }
        let vitals = ExtensionValidator.validate(at: ExtFixtures.builtIn("system-vitals"), paths: paths, resolver: Self.resolver)
        #expect(vitals.summary?.texts == ["Can run /usr/bin/pmset", "No access to your files or the internet"])
        #expect(vitals.toolRisks.map(\.risk) == [.low, .low, .low, .low])
        // A program of its own, inside the signed app: no interpreter to find on the Mac.
        #expect(vitals.launch?.interpreter == nil && vitals.launch?.program == "bin/ext-system-vitals")
        #expect(vitals.text.contains("Valid."))
        guard ExtFixtures.hasAddons else { return }
        let images = ExtensionValidator.validate(at: ExtFixtures.builtIn("images"), paths: paths, resolver: Self.resolver)
        #expect(images.summary?.texts == ["Can read and change files in a folder you name, for that request only, once you approve it",
                                          "Can use the Mac's graphics hardware for pictures"])
    }

    /// A tool whose calls go to a device the person paired names the parameter that holds it (D72).
    @Test func aPairedDeviceParameterNeedsItsReach() throws {
        #expect(fields(try validate(ExtFixtures.manifest(tools: ["echo": ["reach": "paired", "device": "tv"]]), folder: "p1")).isEmpty)
        #expect(fields(try validate(ExtFixtures.manifest(tools: ["echo": ["reach": "paired"]]), folder: "p2")).isEmpty)
        #expect(fields(try validate(ExtFixtures.manifest(tools: ["echo": ["device": "tv"]]), folder: "p3")) == ["tools.echo.device"])
        #expect(fields(try validate(ExtFixtures.manifest(tools: ["echo": ["reach": "paired", "device": "TV!"]]), folder: "p4")) == ["tools.echo.device"])
        let both: JSONValue = ["echo": ["reach": "paired", "device": "file", "paths": ["file": "read"]]]
        #expect(fields(try validate(ExtFixtures.manifest(tools: both), folder: "p5")) == ["tools.echo.device"], "a device isn't a path")
    }

    @Test func unknownKeysAreRejectedAnywhere() throws {
        var m = ExtFixtures.manifest(extra: ["homepage": "https://example.com"])
        #expect(fields(try validate(m)) == ["homepage"])
        m = ExtFixtures.manifest(permissions: ["netwrok": true])
        #expect(fields(try validate(m, folder: "a")) == ["permissions.netwrok"])
        m = ExtFixtures.manifest(tools: ["echo": ["risk": "low", "danger": true]])
        #expect(fields(try validate(m, folder: "b")) == ["tools.echo.danger"])
        m = ExtFixtures.manifest(permissions: ["files": ["reed": []]])
        #expect(fields(try validate(m, folder: "c")) == ["permissions.files.reed"])
    }

    @Test func missingNetworkMeansFalseAndWrongTypesAreNamed() throws {
        let ok = try validate(ExtFixtures.manifest())
        #expect(ok.isValid)
        #expect(ok.permissions?.network == false)
        let bad = try validate(ExtFixtures.manifest(permissions: ["network": "yes"]), folder: "x")
        #expect(bad.errors.first?.field == "permissions.network")
        #expect(bad.errors.first?.message.contains("true or false") == true)
        let unknownRisk = try validate(ExtFixtures.manifest(tools: ["echo": ["risk": "tiny"]]), folder: "y")
        #expect(unknownRisk.errors.first?.field == "tools.echo.risk")
    }

    @Test func aTaglineIsOneShortLine() throws {
        #expect(try validate(ExtFixtures.manifest(extra: ["tagline": "Zip and unzip files"])).isValid)
        for (i, bad) in [String(repeating: "a", count: 61), "Two\nlines", ""].enumerated() {
            #expect(fields(try validate(ExtFixtures.manifest(extra: ["tagline": .string(bad)]), folder: "t\(i)")) == ["tagline"], "\(bad)")
        }
    }

    @Test func theLineUnderTheNameIsTheTaglineOrTheFirstSentence() {
        #expect(ExtensionTagline.line(tagline: "Exact sums", description: "Long. Longer.") == "Exact sums")
        #expect(ExtensionTagline.line(tagline: nil, description: "Weighs 3.5 kg in a click. And more.") == "Weighs 3.5 kg in a click.")
        #expect(ExtensionTagline.line(tagline: " ", description: "One sentence only") == "One sentence only")
        #expect(ExtensionTagline.line(tagline: nil, description: nil) == "")
    }

    @Test func badIdsAreRejected() throws {
        for (i, id) in ["Dev.Test", "devtest", "dev..x", ".dev.x", "dev.x_y", "dev." + String(repeating: "a", count: 61)].enumerated() {
            let r = try validate(ExtFixtures.manifest(id: id), folder: "id\(i)")
            #expect(fields(r).contains("id"), "\(id)")
        }
    }

    @Test func idMustMatchTheInstalledFolder() throws {
        let installed = try validate(ExtFixtures.manifest(), folder: "other", mode: .installed)
        #expect(installed.errors.first?.message.contains("doesn't match") == true)
        let source = try validate(ExtFixtures.manifest(), folder: "other2")
        #expect(source.isValid)
        #expect(source.warnings.count == 1)
        let short = try validate(ExtFixtures.manifest(), folder: "sample")
        #expect(short.isValid && short.warnings.isEmpty)
        // A gallery pack unpacks to <name>.sidefolkaddon/Contents/Resources: the bundle names it, not "Resources".
        let pack = try validate(ExtFixtures.manifest(), folder: "sample.sidefolkaddon/Contents/Resources")
        #expect(pack.isValid && pack.warnings.isEmpty)
        let wrongPack = try validate(ExtFixtures.manifest(), folder: "other3.sidefolkaddon/Contents/Resources")
        #expect(wrongPack.warnings.first?.contains("“other3”") == true)
        let exact = try validate(ExtFixtures.manifest(), folder: "dev.test.sample", mode: .installed)
        #expect(exact.isValid)
    }

    @Test func runCommandCannotEscapeTheFolder() throws {
        #expect(try validate(ExtFixtures.manifest(args: ["../server.py"]), folder: "r1").errors.first?.message == "can't use “..”.")
        #expect(fields(try validate(ExtFixtures.manifest(args: ["/etc/passwd"]), folder: "r2")) == ["run.args[0]"])
        #expect(fields(try validate(ExtFixtures.manifest(args: ["-c", "print(1)"]), folder: "r3")) == ["run.args[0]"])
        #expect(fields(try validate(ExtFixtures.manifest(args: ["missing.py"]), folder: "r4")) == ["run.args[0]"])

        var m = ExtFixtures.manifest()
        if case .object(var o) = m { o["run"] = ["command": "/usr/bin/python3", "args": ["server.py"]]; m = .object(o) }
        #expect(try validate(m, folder: "r5").errors.first?.message.contains("isn't supported") == true)
        if case .object(var o) = m { o["run"] = ["command": "ruby", "args": ["server.py"]]; m = .object(o) }
        #expect(fields(try validate(m, folder: "r6")) == ["run.command"])

        // A script that is a link: outside the folder, and inside it.
        let secret = root.appendingPathComponent("secret.py")
        try Data("x".utf8).write(to: secret)
        let out = root.appendingPathComponent("r7")
        try ExtFixtures.makeExtension(at: out, manifest: ExtFixtures.manifest(args: ["link.py"]))
        try FileManager.default.createSymbolicLink(atPath: out.appendingPathComponent("link.py").path, withDestinationPath: secret.path)
        let r7 = ManifestValidator(paths: paths, resolver: Self.resolver).validate(folder: out)
        #expect(r7.errors.first?.message.contains("points outside") == true)
        let inside = root.appendingPathComponent("r8")
        try ExtFixtures.makeExtension(at: inside, manifest: ExtFixtures.manifest(args: ["link.py"]), files: ["server.py": "x"])
        try FileManager.default.createSymbolicLink(atPath: inside.appendingPathComponent("link.py").path, withDestinationPath: "server.py")
        let r8 = ManifestValidator(paths: paths, resolver: Self.resolver).validate(folder: inside)
        #expect(r8.errors.first?.message.contains("is a link") == true)
    }

    @Test func compiledProgramsInsideTheFolder() throws {
        var m = ExtFixtures.manifest()
        if case .object(var o) = m { o["run"] = ["command": "bin/tool"]; m = .object(o) }
        let script = try validate(m, folder: "p1", files: ["bin/tool": "#!/bin/sh\necho hi\n"])
        #expect(script.errors.first?.message.contains("isn't executable") == true)
        let dir = root.appendingPathComponent("p1/bin/tool").path
        chmod(dir, 0o755)
        let again = ManifestValidator(paths: paths, resolver: Self.resolver).validate(folder: root.appendingPathComponent("p1"))
        #expect(again.errors.first?.message.contains("compiled program") == true)

        let native = root.appendingPathComponent("p2")
        try ExtFixtures.makeExtension(at: native, manifest: m)
        try FileManager.default.createDirectory(at: native.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(atPath: "/usr/bin/true", toPath: native.appendingPathComponent("bin/tool").path)
        let r = ManifestValidator(paths: paths, resolver: Self.resolver).validate(folder: native)
        #expect(r.isValid, "\(r.errors)")
        #expect(r.launch?.interpreter == nil)
        #expect(r.launch?.program == "bin/tool")
    }

    @Test func filePathsAreCanonicalAndChecked() throws {
        let granted = root.appendingPathComponent("granted")
        try FileManager.default.createDirectory(at: granted, withIntermediateDirectories: true)
        let viaVar = granted.path.replacingOccurrences(of: "/private/var/", with: "/var/")
        let ok = try validate(ExtFixtures.manifest(permissions: ["files": ["read": [.string(viaVar)]]]), folder: "f0")
        #expect(ok.isValid, "\(ok.errors)")
        #expect(ok.permissions?.read == [granted.path])

        let bad: [String] = ["Documents", "~/Doc\"s", "~/Docs\nx", "~/Docs\\x", "~/.ssh", "~/Library/Keychains", "~", "/",
                             "~/../x", paths.home.appendingPathComponent("Extensions").path]
        for (i, path) in bad.enumerated() {
            let r = try validate(ExtFixtures.manifest(permissions: ["files": ["read": [.string(path)]]]), folder: "f\(i + 1)")
            #expect(fields(r) == ["permissions.files.read[0]"], "\(path): \(r.errors)")
        }
        let write = try validate(ExtFixtures.manifest(permissions: ["files": ["write": ["~/.zshrc"]]]), folder: "fw")
        #expect(fields(write) == ["permissions.files.write[0]"])
    }

    @Test func execEntriesMustBeFixedProgramsOutsideWritablePlaces() throws {
        func exec(_ entries: [String], write: [String] = [], folder: String) throws -> ValidationReport {
            try validate(ExtFixtures.manifest(permissions: ["exec": .array(entries.map { .string($0) }),
                                                            "files": ["write": .array(write.map { .string($0) })]]), folder: folder)
        }
        #expect(fields(try exec(["pmset"], folder: "e1")) == ["permissions.exec[0]"])
        #expect(fields(try exec(["/usr/bin/nope-\(UUID().uuidString)"], folder: "e2")) == ["permissions.exec[0]"])
        #expect(fields(try exec(["/usr/bin"], folder: "e3")) == ["permissions.exec[0]"])

        let link = root.appendingPathComponent("true-link")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "/usr/bin/true")
        #expect(try exec([link.path], folder: "e4").errors.first?.message.contains("is a link") == true)

        let writable = root.appendingPathComponent("writable")
        try FileManager.default.createDirectory(at: writable, withIntermediateDirectories: true)
        let tool = writable.appendingPathComponent("tool")
        try FileManager.default.copyItem(atPath: "/usr/bin/true", toPath: tool.path)
        chmod(tool.path, 0o755)
        let inside = try exec([tool.path], write: [writable.path], folder: "e5")
        #expect(inside.errors.first?.message.contains("can write to") == true)
        #expect(try exec([tool.path], folder: "e6").isValid)
        chmod(tool.path, 0o775)
        #expect(try exec([tool.path], folder: "e7").errors.first?.message.contains("other users") == true)

        let shell = try exec(["/bin/sh"], folder: "e8")
        #expect(shell.isValid)
        #expect(shell.warnings.contains { $0.contains("can run anything") })
        #expect(shell.permissions?.dangerousExec == ["/bin/sh"])
        #expect(shell.summary?.lines.contains { $0.kind == .exec && $0.caution } == true)
    }

    @Test func toolNamesAreStrictAndNamespaced() throws {
        let r = try validate(ExtFixtures.manifest(tools: ["Battery": [:], "bat-tery": [:], "ok_1": [:]]), folder: "t1")
        #expect(fields(r).sorted() == ["tools.Battery", "tools.bat-tery"])
        let longId = "dev.test." + String(repeating: "x", count: 40)
        let long = try validate(ExtFixtures.manifest(id: longId, tools: .object([String(repeating: "y", count: 20): .object([:])])),
                                folder: "t2")
        #expect(long.errors.first?.message.contains("longer than 64") == true)
    }

    @Test func oversizedManifestIsRejected() throws {
        let padding = String(repeating: " ", count: 70 * 1024)
        let dir = root.appendingPathComponent("big")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data((ExtFixtures.manifest().jsonString + padding).utf8).write(to: dir.appendingPathComponent(ExtensionManifest.fileName))
        let r = ManifestValidator(paths: paths, resolver: Self.resolver).validate(folder: dir)
        #expect(r.errors.first?.message.contains("64 KiB") == true)
    }

    @Test func sidefolkVersionRequirement() throws {
        #expect(try validate(ExtFixtures.manifest(extra: ["sidefolk": ">=0.1"]), folder: "v1").isValid)
        #expect(try validate(ExtFixtures.manifest(extra: ["sidefolk": ">=99.0"]), folder: "v2").errors.first?.message.contains("needs Sidefolk") == true)
        #expect(fields(try validate(ExtFixtures.manifest(extra: ["sidefolk": "~1.0"]), folder: "v3")) == ["sidefolk"])
        #expect(ManifestValidator.satisfies(">=1.0.1", current: "1.0.0") == false)
        #expect(ManifestValidator.satisfies(">= 1", current: "1.0.0") == true)
    }

    @Test func riskFloorsCanBeRaisedNeverLowered() {
        let none = ExtensionPermissions()
        #expect(ExtensionRisk.effective(declared: .low, permissions: none, kind: .sidefolk) == .low)
        #expect(ExtensionRisk.effective(declared: nil, permissions: none, kind: .sidefolk) == .medium)
        #expect(ExtensionRisk.effective(declared: .high, permissions: none, kind: .sidefolk) == .high)
        #expect(ExtensionRisk.effective(declared: .low, permissions: ExtensionPermissions(network: true), kind: .sidefolk) == .medium)
        #expect(ExtensionRisk.effective(declared: .low, permissions: ExtensionPermissions(write: ["/x"]), kind: .sidefolk) == .medium)
        #expect(ExtensionRisk.effective(declared: .low, permissions: ExtensionPermissions(exec: ["/bin/sh"]), kind: .sidefolk) == .medium)
        #expect(ExtensionRisk.effective(declared: .low, permissions: ExtensionPermissions(exec: ["/usr/bin/pmset"]), kind: .sidefolk) == .low)
        #expect(ExtensionRisk.effective(declared: .low, permissions: nil, kind: .mcp) == .medium)
    }

    @Test func watcherSettings() throws {
        let bad = try validate(ExtFixtures.manifest(extra: ["watchers": ["w": ["title": "W", "config": ["n": ["type": "integer", "default": "3"]]]]]), folder: "w1")
        #expect(fields(bad) == ["watchers.w.config.n.default"])
        let fields: [String: ExtensionManifest.ConfigField] = [
            "below": .init(type: .integer, default: 20, minimum: 1, maximum: 99),
            "label": .init(type: .string, required: true),
        ]
        #expect(try WatcherConfig.validate(["label": "x"], fields: fields) == ["label": "x", "below": 20])
        #expect(throws: UserFacingError.self) { try WatcherConfig.validate(["label": "x", "extra": 1], fields: fields) }
        #expect(throws: UserFacingError.self) { try WatcherConfig.validate(["label": "x", "below": 2.5], fields: fields) }
        #expect(throws: UserFacingError.self) { try WatcherConfig.validate(["label": "x", "below": 100], fields: fields) }
        #expect(throws: UserFacingError.self) { try WatcherConfig.validate(["below": 5], fields: fields) }
    }
}
