import Foundation

/// Takes an offer to a new copy ready to swap in (D46): downloads the disk image, checks its size and SHA-256,
/// mounts it out of sight, checks the app inside (this bundle id, this release, signed with this developer's
/// Developer ID and notarized), copies it beside the running app, checks the copy again and only then removes its
/// download mark. When the running copy can't replace itself, the checked disk image goes to Downloads instead.
public actor UpdateInstaller {
    public enum Step: Sendable, Equatable {
        case downloading(received: Int64, total: Int64)
        case checking
        case installing
    }

    public enum Prepared: Sendable, Equatable {
        /// Ready to swap in with `install`.
        case staged(URL)
        /// The disk image is in the person's Downloads folder, for this reason.
        case downloaded(URL, InstallPlan.Reason)
    }

    private let app: RunningApp
    private let workFolder: URL
    private let downloadsFolder: URL
    private let downloader: any UpdateDownloading
    private let images: any DiskImageMounting
    private let code: any CodeChecking
    private let place: @Sendable (URL) -> InstallPlan.Place
    private let relaunch: Relauncher

    /// Opens `app` once process `pid` has quit and removes `leftover` (`BundleSwap.relaunch`); with no `app`, only
    /// removes it.
    public typealias Relauncher = @Sendable (_ pid: Int32, _ app: URL?, _ leftover: URL, _ environment: [String: String]) throws -> Void

    /// - Parameters:
    ///   - workFolder: where downloads and mounts go while they are needed (`SidefolkPaths.updates`).
    ///   - downloadsFolder: where the disk image is left when the app can't replace itself.
    public init(app: RunningApp, workFolder: URL, downloadsFolder: URL,
                downloader: any UpdateDownloading = UpdateDownloader(), images: any DiskImageMounting = DiskImages(),
                code: any CodeChecking = CodeCheck(), place: @escaping @Sendable (URL) -> InstallPlan.Place = InstallPlan.Place.of,
                relaunch: @escaping Relauncher = BundleSwap.relaunch) {
        self.app = app
        self.workFolder = workFolder
        self.downloadsFolder = downloadsFolder
        self.downloader = downloader
        self.images = images
        self.code = code
        self.place = place
        self.relaunch = relaunch
    }

    public nonisolated var plan: InstallPlan { InstallPlan.decide(app, place: place(app.bundle)) }

    public func prepare(_ offer: UpdateOffer, step: @escaping @Sendable (Step) -> Void) async throws -> Prepared {
        let plan = self.plan
        try FileManager.default.createDirectory(at: workFolder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let image = workFolder.appendingPathComponent(offer.image.name)
        defer { try? FileManager.default.removeItem(at: image) }
        try await fetch(offer, to: image, step: step)
        try Task.checkCancellation()

        if case .download(let reason) = plan {
            return .downloaded(try keep(image, named: offer.image.name), reason)
        }
        guard let requirement = app.signing?.replacementRequirement else { throw UserFacingError("This copy of Sidefolk can't update itself.") }
        step(.checking)
        let mount = try await images.attach(image, under: workFolder)
        let staged = BundleSwap.stagingURL(beside: app.bundle, version: offer.version)
        do {
            let candidate = try findApp(in: mount)
            try check(candidate, offer: offer, requirement: requirement)
            try Task.checkCancellation()
            step(.installing)
            try await BundleSwap.copy(candidate, to: staged)
            await images.detach(mount)
            // Checked again where it will run: the copy, not just the image it came from.
            try check(staged, offer: offer, requirement: requirement)
            BundleSwap.clearQuarantine(staged)
            return .staged(staged)
        } catch {
            await images.detach(mount)
            try? FileManager.default.removeItem(at: staged)
            throw error
        }
    }

    /// Exchanges the staged copy with the running one and arranges for it to open once this process has quit.
    /// The caller quits right after. On failure nothing has changed.
    public nonisolated func install(_ staged: URL, environment: [String: String] = [:]) throws {
        try BundleSwap.swap(staged, app.bundle)
        do {
            try relaunch(app.pid, app.bundle, staged, environment)
        } catch {
            // Without a way back up, undo the swap rather than quit into nothing.
            try? BundleSwap.swap(staged, app.bundle)
            throw UserFacingError("Sidefolk couldn't arrange to reopen, so the update was put back.", detail: String(describing: error))
        }
    }

    /// Exchanges the staged copy with the running one as Sidefolk quits, without opening it (D70): the person
    /// asked to quit, and the next launch is the new version. The old copy goes once this process has; if that
    /// can't be arranged, the next launch's `removeLeftovers` takes it.
    public nonisolated func installAtQuit(_ staged: URL) throws {
        try BundleSwap.swap(staged, app.bundle)
        try? relaunch(app.pid, nil, staged, [:])
    }

    /// Clears what an earlier update left: downloads and mounts in the work folder, staged copies beside the app.
    public func removeLeftovers() async {
        let fm = FileManager.default
        for name in (try? fm.contentsOfDirectory(atPath: workFolder.path)) ?? [] {
            let url = workFolder.appendingPathComponent(name)
            // A mount left behind by a crash is detached first; removing files under it would fail anyway.
            if (try? url.resourceValues(forKeys: [.isVolumeKey]))?.isVolume == true { await images.detach(url) }
            try? fm.removeItem(at: url)
        }
        if place(app.bundle).folderWritable { BundleSwap.removeLeftovers(beside: app.bundle) }
    }

    // MARK: Steps

    private func fetch(_ offer: UpdateOffer, to image: URL, step: @escaping @Sendable (Step) -> Void) async throws {
        let total = offer.image.size
        step(.downloading(received: 0, total: total))
        var expected = offer.image.sha256
        if let checksum = offer.checksum {
            let file = workFolder.appendingPathComponent(checksum.name)
            defer { try? FileManager.default.removeItem(at: file) }
            try await downloader.download(checksum.url, to: file, expectedBytes: min(checksum.size, 4096)) { _ in }
            let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            guard let hex = FileDigest.parse(text, for: offer.image.name) else {
                throw UserFacingError("The release's checksum file can't be read, so the update wasn't installed.")
            }
            // GitHub's own digest and the file the release workflow wrote must agree.
            if let github = expected, github != hex { throw UserFacingError("The release's checksums disagree, so the update wasn't installed.") }
            expected = hex
        }
        guard let expected else { throw UserFacingError("The release has no checksum to check the download against, so it wasn't installed.") }

        try await downloader.download(offer.image.url, to: image, expectedBytes: total) { step(.downloading(received: $0, total: total)) }
        step(.checking)
        let size = (try? FileManager.default.attributesOfItem(atPath: image.path)[.size] as? NSNumber)?.int64Value
        guard size == total else { throw UserFacingError("The download isn't the size the release gives, so it wasn't installed.") }
        guard try FileDigest.sha256(image) == expected else {
            throw UserFacingError("The download doesn't match the release's checksum, so it wasn't installed.",
                                  recovery: "Try again; if it happens again, download it from the release page.")
        }
    }

    /// The one app at the top of the image.
    private func findApp(in mount: URL) throws -> URL {
        let apps = ((try? FileManager.default.contentsOfDirectory(atPath: mount.path)) ?? []).filter { $0.hasSuffix(".app") }
        guard apps.count == 1 else { throw UserFacingError("The disk image doesn't hold one Sidefolk app, so nothing was installed.") }
        return mount.appendingPathComponent(apps[0], isDirectory: true)
    }

    /// The same app, the release it claims to be, then the signature and notarization.
    private func check(_ candidate: URL, offer: UpdateOffer, requirement: String) throws {
        let info = NSDictionary(contentsOf: candidate.appendingPathComponent("Contents/Info.plist")) as? [String: Any] ?? [:]
        guard let id = info["CFBundleIdentifier"] as? String, id == app.bundleID else {
            throw UserFacingError("The disk image holds a different app, so nothing was installed.")
        }
        guard (info[RunningApp.releaseKey] as? String).flatMap(ReleaseVersion.init) == offer.version else {
            throw UserFacingError("The app in the disk image isn't the version the release names, so nothing was installed.")
        }
        try code.check(candidate, requirement: requirement)
    }

    /// Moves the checked image into Downloads under a name that is free.
    private func keep(_ image: URL, named name: String) throws -> URL {
        let fm = FileManager.default
        let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        var target = downloadsFolder.appendingPathComponent(name)
        var n = 2
        while fm.fileExists(atPath: target.path) {
            target = downloadsFolder.appendingPathComponent("\(base) \(n).\(ext)")
            n += 1
        }
        try fm.createDirectory(at: downloadsFolder, withIntermediateDirectories: true)
        try fm.moveItem(at: image, to: target)
        return target
    }
}
