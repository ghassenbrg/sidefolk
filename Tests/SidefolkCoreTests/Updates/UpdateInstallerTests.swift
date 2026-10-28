import Foundation
import Security
import Synchronization
import Testing
@testable import SidefolkCore

/// The updater's install path on temporary folders with made-up bundles: nothing here touches /Applications,
/// a real Sidefolk or the network.
@Suite struct UpdateInstallerTests {
    static let team = "ABCDE12345", id = "app.sidefolk.Sidefolk"
    static let developer = SigningFacts(teamID: team, identifier: id, adHoc: false, developerID: true)
    static let writable = InstallPlan.Place(translocated: false, readOnlyVolume: false, folderWritable: true)

    /// A folder for one test: Applications/ with the running copy, Mount/ with the new one, Files/ and Downloads/.
    struct Scene {
        let root: URL
        var applications: URL { root.appendingPathComponent("Applications") }
        var running: URL { applications.appendingPathComponent("Sidefolk.app") }
        var mount: URL { root.appendingPathComponent("Mount") }
        var files: URL { root.appendingPathComponent("Files") }
        var downloads: URL { root.appendingPathComponent("Downloads") }
        var work: URL { root.appendingPathComponent("Work") }

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("sidefolk-update-\(UUID().uuidString)")
            for dir in [applications, mount, files] { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
            try Self.bundle(at: running, id: id, release: "0.1.0-snapshot.411", marker: "old")
            try Self.bundle(at: mount.appendingPathComponent("Sidefolk.app"), id: id, release: "0.1.0-snapshot.430", marker: "new")
        }

        static func bundle(at url: URL, id: String, release: String?, marker: String) throws {
            let contents = url.appendingPathComponent("Contents")
            try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
            var info: [String: Any] = ["CFBundleIdentifier": id, "CFBundleExecutable": "Sidefolk"]
            if let release { info[RunningApp.releaseKey] = release }
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: contents.appendingPathComponent("Info.plist"))
            try Data(marker.utf8).write(to: contents.appendingPathComponent("MacOS/Sidefolk"))
        }

        func marker(_ app: URL) -> String? {
            (try? Data(contentsOf: app.appendingPathComponent("Contents/MacOS/Sidefolk"))).map { String(decoding: $0, as: UTF8.self) }
        }

        /// Writes the disk image (any bytes stand in) and its checksum file, and the offer naming them.
        func offer(image: Data = Data("disk image".utf8), checksum: String? = nil, githubDigest: String?? = .none,
                   size: Int64? = nil) throws -> UpdateOffer {
            let name = "Sidefolk-0.1.0-snapshot.430.dmg"
            try image.write(to: files.appendingPathComponent(name))
            let real = try FileDigest.sha256(files.appendingPathComponent(name))
            try Data("\(checksum ?? real)  \(name)\n".utf8).write(to: files.appendingPathComponent(name + ".sha256"))
            let base = "https://github.com/ghassenbrg/sidefolk/releases/download/v0.1.0-snapshot.430/"
            let digest: String? = switch githubDigest { case .none: real; case .some(let d): d }
            return UpdateOffer(version: ReleaseVersion("0.1.0-snapshot.430")!, tag: "v0.1.0-snapshot.430", title: "", notes: "",
                               page: URL(string: "https://github.com")!, published: nil, isSnapshot: true,
                               image: .init(name: name, size: size ?? Int64(image.count), url: URL(string: base + name)!, sha256: digest),
                               checksum: .init(name: name + ".sha256", size: 98, url: URL(string: base + name + ".sha256")!))
        }

        /// Never opens anything: `relaunched` records what would have been opened.
        func installer(signing: SigningFacts? = developer, release: String? = "0.1.0-snapshot.411",
                       place: InstallPlan.Place = writable, code: FakeCode = FakeCode(),
                       relaunched: Recorder<String> = Recorder(), relaunchFails: Bool = false) -> (UpdateInstaller, FakeImages) {
            let app = RunningApp(bundle: running, bundleID: id, release: release.flatMap(ReleaseVersion.init), signing: signing, pid: 4242)
            let images = FakeImages(mount: mount)
            return (UpdateInstaller(app: app, workFolder: work, downloadsFolder: downloads, downloader: FakeDownloader(files: files),
                                    images: images, code: code, place: { _ in place },
                                    relaunch: { pid, app, leftover, _ in
                                        if relaunchFails { throw POSIXError(.EAGAIN) }
                                        relaunched.add("\(pid) \(app.lastPathComponent) \(leftover.lastPathComponent)")
                                    }), images)
        }
    }

    @Test func stagesACheckedCopyBesideTheAppWithoutTheDownloadMark() async throws {
        let scene = try Scene()
        // The image's files carry a download mark, as a mounted quarantined image's do.
        let newApp = scene.mount.appendingPathComponent("Sidefolk.app")
        for path in [newApp.path, newApp.appendingPathComponent("Contents/MacOS/Sidefolk").path] {
            #expect(setxattr(path, "com.apple.quarantine", "0081;00000000;Sidefolk;", 23, 0, XATTR_NOFOLLOW) == 0)
        }
        let code = FakeCode(), relaunched = Recorder<String>()
        let (installer, images) = scene.installer(code: code, relaunched: relaunched)
        let steps = Recorder<UpdateInstaller.Step>()
        let prepared = try await installer.prepare(try scene.offer()) { steps.add($0) }

        let staged = scene.applications.appendingPathComponent(".Sidefolk-update-0.1.0-snapshot.430.app")
        #expect(prepared == .staged(staged))
        #expect(scene.marker(staged) == "new")
        #expect(scene.marker(scene.running) == "old")
        for path in [staged.path, staged.appendingPathComponent("Contents/MacOS/Sidefolk").path] {
            #expect(getxattr(path, "com.apple.quarantine", nil, 0, 0, XATTR_NOFOLLOW) == -1)
        }
        // Checked in the image and again where it will run, against this developer's requirement.
        #expect(code.checked.map(\.lastPathComponent) == ["Sidefolk.app", ".Sidefolk-update-0.1.0-snapshot.430.app"])
        #expect(code.requirements.allSatisfy { $0 == Self.developer.replacementRequirement })
        #expect(images.detached == [scene.mount])
        let seen = steps.all
        #expect(seen.first == .downloading(received: 0, total: 10))
        #expect(seen.contains(.checking) && seen.last == .installing)
        // The download is gone once it's been used.
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: scene.work.path)) ?? []).isEmpty)

        try installer.install(staged)
        #expect(scene.marker(scene.running) == "new")
        #expect(scene.marker(staged) == "old")
        #expect(relaunched.all == ["4242 Sidefolk.app .Sidefolk-update-0.1.0-snapshot.430.app"])
    }

    @Test func withoutAWayToReopenTheSwapIsUndone() throws {
        let scene = try Scene()
        let staged = BundleSwap.stagingURL(beside: scene.running, version: ReleaseVersion("0.1.0-snapshot.430")!)
        try Scene.bundle(at: staged, id: Self.id, release: "0.1.0-snapshot.430", marker: "new")
        let (installer, _) = scene.installer(relaunchFails: true)
        #expect(throws: UserFacingError.self) { try installer.install(staged) }
        #expect(scene.marker(scene.running) == "old")
        #expect(scene.marker(staged) == "new")
    }

    /// The waiting shell itself, pointed at a process that has already exited and at a bundle `open` can't
    /// launch (it isn't a folder): it removes only a leftover with the staging prefix.
    @Test func relaunchShellRemovesOnlyTheLeftover() async throws {
        let scene = try Scene()
        let leftover = scene.applications.appendingPathComponent(".Sidefolk-update-0.1.0-snapshot.411.app")
        let other = scene.applications.appendingPathComponent("Other.app")
        for app in [leftover, other] { try Scene.bundle(at: app, id: Self.id, release: nil, marker: "x") }
        let gone = try PosixSpawn.run("/usr/bin/true", arguments: [], environment: [:], searchPath: false, options: .init())
        _ = await PosixSpawn.waitAsync(gone)
        let missing = scene.root.appendingPathComponent("no-such-file")
        try BundleSwap.relaunch(after: gone, open: missing, removing: leftover)
        try BundleSwap.relaunch(after: gone, open: missing, removing: other)
        for _ in 0..<100 where FileManager.default.fileExists(atPath: leftover.path) { try await Task.sleep(for: .milliseconds(50)) }
        #expect(!FileManager.default.fileExists(atPath: leftover.path))
        try await Task.sleep(for: .milliseconds(300))
        #expect(FileManager.default.fileExists(atPath: other.path))
    }

    @Test func refusesADownloadThatDoesntMatch() async throws {
        let cases: [(String, (Scene) throws -> UpdateOffer)] = [
            ("checksum", { try $0.offer(checksum: String(repeating: "0", count: 64), githubDigest: .some(nil)) }),
            ("checksums disagree", { try $0.offer(githubDigest: String(repeating: "1", count: 64)) }),
            ("size", { try $0.offer(size: 999) }),
            ("checksum file", { try $0.offer(checksum: "not a digest") }),
        ]
        for (name, make) in cases {
            let scene = try Scene()
            let (installer, images) = scene.installer()
            await #expect(throws: UserFacingError.self, "\(name)") { _ = try await installer.prepare(try make(scene)) { _ in } }
            #expect(images.attached == 0, "\(name)")
            #expect(scene.marker(scene.running) == "old")
        }
    }

    @Test func refusesAnotherAppAnotherVersionOrAnotherSigner() async throws {
        for wrong in ["id", "release", "signature", "two apps"] {
            let scene = try Scene()
            let newApp = scene.mount.appendingPathComponent("Sidefolk.app")
            switch wrong {
            case "id": try Scene.bundle(at: newApp, id: "com.example.Other", release: "0.1.0-snapshot.430", marker: "new")
            case "release": try Scene.bundle(at: newApp, id: Self.id, release: "0.1.0-snapshot.429", marker: "new")
            case "two apps": try Scene.bundle(at: scene.mount.appendingPathComponent("Other.app"), id: Self.id, release: nil, marker: "x")
            default: break
            }
            let code = FakeCode(fails: wrong == "signature")
            let (installer, images) = scene.installer(code: code)
            await #expect(throws: UserFacingError.self, "\(wrong)") { _ = try await installer.prepare(try scene.offer()) { _ in } }
            #expect(images.detached == [scene.mount], "\(wrong)")
            let left = try FileManager.default.contentsOfDirectory(atPath: scene.applications.path)
            #expect(left == ["Sidefolk.app"], "\(wrong)")
        }
    }

    @Test func aCopyThatCantReplaceItselfLeavesTheCheckedImageInDownloads() async throws {
        let scene = try Scene()
        try FileManager.default.createDirectory(at: scene.downloads, withIntermediateDirectories: true)
        try Data().write(to: scene.downloads.appendingPathComponent("Sidefolk-0.1.0-snapshot.430.dmg"))
        let (installer, images) = scene.installer(place: .init(translocated: true, readOnlyVolume: false, folderWritable: true))
        let prepared = try await installer.prepare(try scene.offer()) { _ in }
        #expect(prepared == .downloaded(scene.downloads.appendingPathComponent("Sidefolk-0.1.0-snapshot.430 2.dmg"), .translocated))
        #expect(images.attached == 0)
        #expect(scene.marker(scene.running) == "old")
    }

    @Test func planForEachPlace() {
        let app = RunningApp(bundle: URL(fileURLWithPath: "/Applications/Sidefolk.app"), bundleID: Self.id,
                             release: ReleaseVersion("0.1.0"), signing: Self.developer)
        #expect(InstallPlan.decide(app, place: Self.writable) == .replace)
        #expect(InstallPlan.decide(app, place: .init(translocated: true, readOnlyVolume: true, folderWritable: false)) == .download(.translocated))
        #expect(InstallPlan.decide(app, place: .init(translocated: false, readOnlyVolume: true, folderWritable: false)) == .download(.readOnly))
        #expect(InstallPlan.decide(app, place: .init(translocated: false, readOnlyVolume: false, folderWritable: false)) == .download(.notWritable))
        var local = app
        local.release = nil
        #expect(InstallPlan.decide(local, place: Self.writable) == .download(.notPublished))
        #expect(local.version == ReleaseVersion("\(SidefolkVersion.current)-dev"))
        for signing in [nil, SigningFacts(teamID: nil, identifier: Self.id, adHoc: true, developerID: false),
                        SigningFacts(teamID: Self.team, identifier: Self.id, adHoc: false, developerID: false)] {
            var other = app
            other.signing = signing
            #expect(InstallPlan.decide(other, place: Self.writable) == .download(.notDeveloperID))
        }
    }

    @Test func placeIsReadFromTheDisk() throws {
        let scene = try Scene()
        let place = InstallPlan.Place.of(scene.running)
        #expect(place == Self.writable)
        #expect(InstallPlan.Place.of(URL(fileURLWithPath: "/private/var/folders/x/AppTranslocation/ABC/d/Sidefolk.app")).translocated)
        #expect(!InstallPlan.Place.of(URL(fileURLWithPath: "/System/Applications/Calculator.app")).folderWritable)
    }

    @Test func requirementComesFromTheSignatureThatRuns() {
        let info: [String: Any] = [kSecCodeInfoTeamIdentifier as String: Self.team, kSecCodeInfoIdentifier as String: Self.id,
                                   kSecCodeInfoFlags as String: NSNumber(value: 0x10000)]
        let facts = SigningFacts(info: info, leafName: "Developer ID Application: Someone (\(Self.team))")
        #expect(facts == Self.developer)
        #expect(facts.replacementRequirement == """
            anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] and certificate 1[field.1.2.840.113635.100.6.2.6] \
            and certificate leaf[subject.OU] = "ABCDE12345" and identifier "app.sidefolk.Sidefolk" and notarized
            """)
        // Apple Development, ad hoc, or anything that could break out of the quotes: no requirement, no self-update.
        #expect(SigningFacts(info: info, leafName: "Apple Development: Someone (XYZ)").replacementRequirement == nil)
        var adHoc = info
        adHoc[kSecCodeInfoFlags as String] = NSNumber(value: 0x2)
        #expect(SigningFacts(info: adHoc, leafName: "Developer ID Application: x").replacementRequirement == nil)
        #expect(SigningFacts(teamID: "AB\" or true", identifier: Self.id, adHoc: false, developerID: true).replacementRequirement == nil)
        #expect(SigningFacts(teamID: Self.team, identifier: "a\" or anchor", adHoc: false, developerID: true).replacementRequirement == nil)
    }

    @Test func realCheckRefusesACopyNotSignedByTheDeveloper() async throws {
        let scene = try Scene()
        let app = scene.mount.appendingPathComponent("Sidefolk.app")
        // A real executable, signed ad hoc as builds without a certificate are.
        try FileManager.default.removeItem(at: app.appendingPathComponent("Contents/MacOS/Sidefolk"))
        try FileManager.default.copyItem(atPath: "/usr/bin/true", toPath: app.appendingPathComponent("Contents/MacOS/Sidefolk").path)
        let signed = try await SystemTool.run("/usr/bin/codesign", ["--force", "--sign", "-", app.path], timeout: 60)
        #expect(signed.status == 0)
        #expect(SigningFacts.of(app)?.adHoc == true)
        let error = #expect(throws: UserFacingError.self) {
            try CodeCheck().check(app, requirement: Self.developer.replacementRequirement!)
        }
        #expect(error?.message.contains("isn't signed and notarized by Sidefolk's developer") == true)
    }

    @Test func swapAndLeftovers() throws {
        let scene = try Scene()
        let staged = BundleSwap.stagingURL(beside: scene.running, version: ReleaseVersion("0.1.0-snapshot.430")!)
        try Scene.bundle(at: staged, id: Self.id, release: "0.1.0-snapshot.430", marker: "new")
        try BundleSwap.swap(staged, scene.running)
        #expect(scene.marker(scene.running) == "new")
        #expect(scene.marker(staged) == "old")
        // Two folders on different volumes (or missing) can't be exchanged: nothing moves.
        #expect(throws: UserFacingError.self) { try BundleSwap.swap(scene.root.appendingPathComponent("missing.app"), scene.running) }
        #expect(scene.marker(scene.running) == "new")

        try Data().write(to: scene.applications.appendingPathComponent(".Sidefolk-update-notes.txt"))
        try Scene.bundle(at: scene.applications.appendingPathComponent("Other.app"), id: "x", release: nil, marker: "x")
        BundleSwap.removeLeftovers(beside: scene.running)
        let left = try FileManager.default.contentsOfDirectory(atPath: scene.applications.path).sorted()
        #expect(left == [".Sidefolk-update-notes.txt", "Other.app", "Sidefolk.app"])
    }

    @Test func digestsAndChecksumLines() throws {
        let scene = try Scene()
        let file = scene.files.appendingPathComponent("x")
        try Data("abc".utf8).write(to: file)
        let abc = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        #expect(try FileDigest.sha256(file) == abc)
        #expect(FileDigest.parse("\(abc)  Sidefolk.dmg\n", for: "Sidefolk.dmg") == abc)
        #expect(FileDigest.parse("\(abc.uppercased()) *Sidefolk.dmg", for: "Sidefolk.dmg") == abc)
        #expect(FileDigest.parse(abc, for: "Sidefolk.dmg") == abc)
        #expect(FileDigest.parse("\(abc)  Other.dmg", for: "Sidefolk.dmg") == nil)
        #expect(FileDigest.parse("abc  Sidefolk.dmg", for: "Sidefolk.dmg") == nil)
        #expect(UpdateDownloader.allowed(URL(string: "https://github.com/a/b")!))
        #expect(UpdateDownloader.allowed(URL(string: "https://release-assets.githubusercontent.com/x")!))
        #expect(!UpdateDownloader.allowed(URL(string: "http://github.com/a/b")!))
        #expect(!UpdateDownloader.allowed(URL(string: "https://github.com.example.com/x")!))
        #expect(!UpdateDownloader.allowed(URL(string: "https://evilgithubusercontent.com/x")!))
    }

    /// A real disk image through hdiutil: made, mounted out of sight, read and detached.
    @Test func mountsADiskImage() async throws {
        let scene = try Scene()
        let image = scene.root.appendingPathComponent("test.dmg")
        let made = try await SystemTool.run("/usr/bin/hdiutil", ["create", "-quiet", "-volname", "SidefolkTest", "-srcfolder",
                                                                 scene.mount.path, "-format", "UDZO", image.path], timeout: 120)
        try #require(made.status == 0)
        try FileManager.default.createDirectory(at: scene.work, withIntermediateDirectories: true)
        let mount = try await DiskImages().attach(image, under: scene.work)
        // Under the work folder (hdiutil names it by its real path, /private/var/…).
        #expect(mount.deletingLastPathComponent().path.hasSuffix(scene.root.lastPathComponent + "/Work"), "\(mount.path)")
        #expect(scene.marker(mount.appendingPathComponent("Sidefolk.app")) == "new")
        await DiskImages().detach(mount)
        #expect(!FileManager.default.fileExists(atPath: mount.appendingPathComponent("Sidefolk.app").path))
    }
}

/// Collects what a callback was given, from any thread.
final class Recorder<T: Sendable>: Sendable {
    private let items = Mutex<[T]>([])
    func add(_ item: T) { items.withLock { $0.append(item) } }
    var all: [T] { items.withLock { $0 } }
}

/// Copies from a folder of files by name, in place of GitHub.
struct FakeDownloader: UpdateDownloading {
    let files: URL

    func download(_ url: URL, to destination: URL, expectedBytes: Int64, progress: @escaping @Sendable (Int64) -> Void) async throws {
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: files.appendingPathComponent(url.lastPathComponent), to: destination)
        progress(expectedBytes)
    }
}

/// "Mounts" by handing back a folder.
final class FakeImages: DiskImageMounting, Sendable {
    let mount: URL
    private let state = Mutex<(attached: Int, detached: [URL])>((0, []))
    var attached: Int { state.withLock { $0.attached } }
    var detached: [URL] { state.withLock { $0.detached } }

    init(mount: URL) { self.mount = mount }

    func attach(_ image: URL, under folder: URL) async throws -> URL {
        state.withLock { $0.attached += 1 }
        return mount
    }

    func detach(_ mountPoint: URL) async { state.withLock { $0.detached.append(mountPoint) } }
}

/// Records what was checked; refuses everything when told to.
final class FakeCode: CodeChecking, Sendable {
    private let fails: Bool
    private let state = Mutex<[(URL, String)]>([])
    var checked: [URL] { state.withLock { $0.map(\.0) } }
    var requirements: [String] { state.withLock { $0.map(\.1) } }

    init(fails: Bool = false) { self.fails = fails }

    func check(_ url: URL, requirement: String) throws {
        state.withLock { $0.append((url, requirement)) }
        if fails { throw UserFacingError("The new version isn't signed and notarized by Sidefolk's developer, so it wasn't installed.") }
    }
}
