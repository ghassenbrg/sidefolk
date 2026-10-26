import Foundation
import Testing
@testable import SidefolkCore

@Suite struct FileAppearsProbeTests {
    let box: Sandbox
    let probe = FileAppearsProbe(settle: 3)

    init() throws { box = try Sandbox() }

    func watcher(_ name: String, gone: Bool = false) throws -> Watcher {
        try probe.made(.make(WatchKind.fileAppears, config: ["path": .string(box.path(name))], condition: gone ? ["gone": true] : .object([:])))
    }

    @Test func triggersWhenTheFileShowsUp() async throws {
        defer { box.cleanUp() }
        var w = try watcher("report.pdf")
        let first = try await probe.step(&w)
        #expect(!first.triggered)
        #expect(first.recheckIn == nil)
        #expect(probe.eventTargets(for: w) == [.directory(box.root)])

        try box.write("report.pdf", "pdf bytes", age: 60)
        let r = try await probe.step(&w, at: Date())
        #expect(r.triggered)
        #expect(r.summary == "report.pdf appeared")
        #expect(r.openTarget == box.path("report.pdf"))
        #expect(try await !probe.step(&w, at: Date()).triggered, "told once")
    }

    @Test func aFileStillBeingWrittenWaitsUntilItSettles() async throws {
        defer { box.cleanUp() }
        var w = try watcher("big.zip")
        _ = try await probe.step(&w)
        try box.write("big.zip", "part one", age: 0)
        let fresh = try await probe.step(&w, at: Date())
        #expect(!fresh.triggered)
        #expect(fresh.recheckIn != nil)

        let later = try await probe.step(&w, at: Date().addingTimeInterval(5))
        #expect(later.triggered)
    }

    @Test func aFileThatIsAlreadyThereIsReportedAsSuch() async throws {
        defer { box.cleanUp() }
        try box.write("here.txt", "x", age: 600)
        var w = try watcher("here.txt")
        let r = try await probe.step(&w, at: Date())
        #expect(r.triggered)
        #expect(r.summary == "here.txt is already there")
    }

    @Test func goneWatchesForDisappearing() async throws {
        defer { box.cleanUp() }
        try box.write("lock.pid", "1", age: 600)
        var w = try watcher("lock.pid", gone: true)
        #expect(try await !probe.step(&w, at: Date()).triggered)
        try box.remove("lock.pid")
        let r = try await probe.step(&w, at: Date())
        #expect(r.triggered)
        #expect(r.summary == "lock.pid is gone")
        #expect(w.lastState?["exists"]?.boolValue == false)
    }

    @Test func eventsFollowTheNearestFolderThatExists() throws {
        defer { box.cleanUp() }
        let w = try watcher("not/yet/there.txt")
        #expect(probe.eventTargets(for: w) == [.directory(box.root)])
    }

    @Test func repeatWatchersFireAgainAfterTheFileCameAndWent() async throws {
        defer { box.cleanUp() }
        var w = try watcher("job.done")
        w.mode = .repeat
        _ = try await probe.step(&w, at: Date())
        try box.write("job.done", "", age: 600)
        #expect(try await probe.step(&w, at: Date()).triggered)
        try box.remove("job.done")
        #expect(try await !probe.step(&w, at: Date()).triggered)
        try box.write("job.done", "", age: 600)
        #expect(try await probe.step(&w, at: Date()).triggered)
    }

    @Test func pathsAreCheckedWhenTheWatcherIsMade() throws {
        defer { box.cleanUp() }
        #expect(throws: WatchError.self) { _ = try probe.made(.make(WatchKind.fileAppears, config: ["path": "relative/file.txt"])) }
        #expect(throws: WatchError.self) { _ = try probe.made(.make(WatchKind.fileAppears, config: ["path": .string(box.root + "/a/../b")])) }
        #expect(throws: WatchError.self) { _ = try probe.made(.make(WatchKind.fileAppears, config: ["path": "~/.ssh/id_ed25519"])) }
        #expect(throws: WatchError.self) { _ = try probe.made(.make(WatchKind.fileAppears, config: ["path": "/etc/hosts"])) }
        #expect(throws: WatchError.self) { _ = try probe.made(.make(WatchKind.fileAppears, config: ["path": ""])) }
        #expect(probe.minimumInterval == 15)
        #expect(probe.defaultInterval == 30)
    }

    @Test func aLinkThatAppearsOnTheWayStopsTheWatcher() async throws {
        defer { box.cleanUp() }
        let other = try Sandbox()
        defer { other.cleanUp() }
        try FileManager.default.createDirectory(atPath: box.path("inbox"), withIntermediateDirectories: true)
        var w = try watcher("inbox/report.pdf")
        _ = try await probe.step(&w)
        try FileManager.default.removeItem(atPath: box.path("inbox"))
        try FileManager.default.createSymbolicLink(atPath: box.path("inbox"), withDestinationPath: other.root)
        await #expect(throws: ProbeError.self) { try await probe.step(&w) }
    }
}

@Suite struct FileChangesProbeTests {
    let box: Sandbox
    let probe = FileChangesProbe()

    init() throws { box = try Sandbox() }

    func watcher(_ name: String) throws -> Watcher {
        try probe.made(.make(WatchKind.fileChanges, config: ["path": .string(box.path(name))]))
    }

    @Test func sizeOrModificationTimeChangesTrigger() async throws {
        defer { box.cleanUp() }
        try box.write("notes.txt", "one", age: 600)
        var w = try watcher("notes.txt")
        #expect(try await !probe.step(&w).triggered, "baseline")
        #expect(try await !probe.step(&w).triggered)
        #expect(probe.eventTargets(for: w) == [.file(box.path("notes.txt"))])

        try box.write("notes.txt", "one two three", age: 300)
        let grown = try await probe.step(&w)
        #expect(grown.triggered)
        #expect(grown.summary == "notes.txt changed")
        #expect(grown.detail?.contains("→") == true)

        try box.setAge("notes.txt", 10) // same size, newer
        let touched = try await probe.step(&w)
        #expect(touched.triggered)
        #expect(touched.detail == "Size unchanged")
        #expect(try await !probe.step(&w).triggered)
    }

    @Test func createdAndDeletedCount() async throws {
        defer { box.cleanUp() }
        var w = try watcher("later.txt")
        #expect(try await !probe.step(&w).triggered)
        #expect(probe.eventTargets(for: w) == [.directory(box.root)])
        try box.write("later.txt", "x")
        let made = try await probe.step(&w)
        #expect(made.summary == "later.txt was created")
        try box.remove("later.txt")
        let gone = try await probe.step(&w)
        #expect(gone.summary == "later.txt was deleted")
    }
}

@Suite struct FolderNewFileProbeTests {
    let box: Sandbox
    let probe = FolderNewFileProbe(settleRecheck: 3)

    init() throws { box = try Sandbox() }

    func watcher(pattern: String? = nil, folder: String = "") throws -> Watcher {
        var config: JSONValue = ["path": .string(folder.isEmpty ? box.root : box.path(folder))]
        if let pattern { config = config.setting("pattern", .string(pattern)) }
        return try probe.made(.make(WatchKind.folderNewFile, config: config, mode: .repeat))
    }

    @Test func existingFilesAreTheBaseline() async throws {
        defer { box.cleanUp() }
        try box.write("old.txt")
        var w = try watcher()
        #expect(try await !probe.step(&w).triggered)
        #expect(try await !probe.step(&w).triggered)
        #expect(probe.eventTargets(for: w) == [.directory(box.root)])
    }

    @Test func aFinishedDownloadIsReportedOnceItsSizeHoldsStill() async throws {
        defer { box.cleanUp() }
        var w = try watcher()
        _ = try await probe.step(&w)

        // Chrome writes report.pdf.crdownload and renames it when done.
        try box.write("report.pdf.crdownload", "half")
        let partial = try await probe.step(&w)
        #expect(!partial.triggered)
        #expect(partial.recheckIn == nil)

        try box.move("report.pdf.crdownload", "report.pdf")
        let renamed = try await probe.step(&w)
        #expect(!renamed.triggered, "a size seen only once is not stable yet")
        #expect(renamed.recheckIn == 3)

        let settled = try await probe.step(&w)
        #expect(settled.triggered)
        #expect(settled.summary == "report.pdf finished downloading")
        #expect(settled.openTarget == box.path("report.pdf"))
        #expect(try await !probe.step(&w).triggered, "reported once")
    }

    @Test func aGrowingFileKeepsWaiting() async throws {
        defer { box.cleanUp() }
        var w = try watcher()
        _ = try await probe.step(&w)
        try box.write("movie.mov", "12345")
        #expect(try await !probe.step(&w).triggered)
        try box.write("movie.mov", "1234567890")
        #expect(try await !probe.step(&w).triggered)
        try box.write("movie.mov", "1234567890abcdef")
        #expect(try await !probe.step(&w).triggered)
        let done = try await probe.step(&w)
        #expect(done.triggered)
        #expect(done.summary == "movie.mov finished downloading", "it was seen growing")
    }

    @Test func partialAndHiddenNamesAreIgnored() async throws {
        defer { box.cleanUp() }
        var w = try watcher()
        _ = try await probe.step(&w)
        for name in ["a.crdownload", "b.download", "c.part", "d.tmp", ".hidden", ".DS_Store", "E.CRDOWNLOAD"] { try box.write(name) }
        #expect(try await !probe.step(&w).triggered)
        #expect(try await !probe.step(&w).triggered)
    }

    @Test func aPatternNarrowsWhatCounts() async throws {
        defer { box.cleanUp() }
        var w = try watcher(pattern: "*.pdf")
        _ = try await probe.step(&w)
        try box.write("notes.txt")
        try box.write("Invoice.PDF")
        _ = try await probe.step(&w)
        let r = try await probe.step(&w)
        #expect(r.triggered)
        #expect(r.summary == "New in \(WatchedPath.name(box.root)): Invoice.PDF")
        #expect(try await !probe.step(&w).triggered, "notes.txt never matches")
    }

    @Test func severalNewFilesAreOneNotice() async throws {
        defer { box.cleanUp() }
        var w = try watcher()
        _ = try await probe.step(&w)
        for n in 1...6 { try box.write("scan\(n).png") }
        _ = try await probe.step(&w)
        let r = try await probe.step(&w)
        #expect(r.triggered)
        #expect(r.summary.hasPrefix("6 new files in"))
        #expect(r.detail == "scan1.png, scan2.png, scan3.png, scan4.png and 2 more")
        #expect(r.openTarget == box.root)
    }

    @Test func aNewFolderCountsAtOnce() async throws {
        defer { box.cleanUp() }
        var w = try watcher()
        _ = try await probe.step(&w)
        try FileManager.default.createDirectory(atPath: box.path("Project"), withIntermediateDirectories: true)
        let r = try await probe.step(&w)
        #expect(r.triggered)
        #expect(r.detail == "A folder")
    }

    @Test func downloadedProgramsOpenTheirFolderNotThemselves() async throws {
        defer { box.cleanUp() }
        var w = try watcher()
        _ = try await probe.step(&w)
        try box.write("Installer.pkg")
        _ = try await probe.step(&w)
        let r = try await probe.step(&w)
        #expect(r.triggered)
        #expect(r.openTarget == box.root, "never open something that would run")
    }

    @Test func namesFromTheOutsideAreCleanedForDisplay() async throws {
        defer { box.cleanUp() }
        var w = try watcher()
        _ = try await probe.step(&w)
        try box.write("evil\u{202E}fdp.exe")
        _ = try await probe.step(&w)
        let r = try await probe.step(&w)
        #expect(r.summary.contains("evilfdp.exe"))
        #expect(!r.summary.unicodeScalars.contains { $0.value == 0x202E })
    }

    @Test func aBigDownloadsFolderCanStillBeWatched() async throws {
        defer { box.cleanUp() }
        for i in 0..<5_100 { FileManager.default.createFile(atPath: box.path("f\(i).txt"), contents: Data()) }
        var w = try watcher()
        let baseline = try await probe.step(&w)
        #expect(!baseline.triggered)
        try box.write("movie.mov")
        _ = try await probe.step(&w)
        let r = try await probe.step(&w)
        #expect(r.triggered)
        #expect(r.summary.contains("movie.mov"))
    }

    @Test func aMissingFolderIsAFailureAndHugeFoldersAreRefused() async throws {
        defer { box.cleanUp() }
        var w = try watcher(folder: "later")
        await #expect(throws: ProbeError.self) { try await probe.step(&w) }
        #expect(FolderNewFileProbe.isIgnored("x.part"))
        #expect(!FolderNewFileProbe.isIgnored("x.partx"))
        #expect(throws: WatchError.self) { _ = try probe.made(.make(WatchKind.folderNewFile, config: ["path": .string(box.root), "pattern": "a/b"])) }
    }
}
