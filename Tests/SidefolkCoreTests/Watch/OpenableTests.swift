import Foundation
import Testing
@testable import SidefolkCore

/// What the "Open" button on a notice is allowed to open: documents, never anything that could run.
@Suite struct OpenableTests {
    let box: Sandbox
    init() throws { box = try Sandbox() }

    func bytes(_ name: String, _ data: [UInt8], mode: Int = 0o644) throws {
        try Data(data).write(to: URL(fileURLWithPath: box.path(name)))
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: box.path(name))
    }

    @Test func documentsOpenThemselves() throws {
        defer { box.cleanUp() }
        for name in ["report.pdf", "Photo.PNG", "notes.txt", "plan.docx", "budget.xlsx", "deck.key", "page.html", "song.mp3"] {
            try box.write(name)
            #expect(WatchedPath.openable(box.path(name)) == box.path(name), "\(name) is a document")
        }
    }

    @Test func programsScriptsAndShortcutsShowTheirFolder() throws {
        defer { box.cleanUp() }
        for name in ["Setup.pkg", "run.sh", "x.command", "link.inetloc", "link.webloc", "link.url", "link.fileloc", "a.terminal",
                     "Tool.app", "plugin.bundle", "x.osax", "x.plugin", "Disk.dmg", "setup.exe", "notes.txt.sh", "macro.docm"] {
            try box.write(name)
            #expect(WatchedPath.openable(box.path(name)) == box.root, "\(name) must not be opened")
        }
    }

    @Test func aFileWithNoExtensionIsNeverOpened() throws {
        defer { box.cleanUp() }
        try box.write("README", "just words")
        #expect(WatchedPath.openable(box.path("README")) == box.root)

        // The audit's case: a script or program with a plain name, exec bit set.
        try bytes("INSTALL", Array("#!/bin/sh\necho hi\n".utf8), mode: 0o755)
        try bytes("tool", [0xCF, 0xFA, 0xED, 0xFE, 0, 0, 0, 0], mode: 0o755)
        #expect(WatchedPath.openable(box.path("INSTALL")) == box.root)
        #expect(WatchedPath.openable(box.path("tool")) == box.root)
    }

    @Test func aProgramInADocumentsClothesIsNotOpened() throws {
        defer { box.cleanUp() }
        try bytes("invoice.pdf", Array("%PDF-1.4".utf8), mode: 0o755)
        try bytes("script.txt", Array("#!/bin/sh\nrm -rf ~\n".utf8))
        try bytes("fake.png", [0xCF, 0xFA, 0xED, 0xFE, 0, 0, 0, 0])
        try bytes("fat.pdf", [0xCA, 0xFE, 0xBA, 0xBE, 0, 0, 0, 2])
        for name in ["invoice.pdf", "script.txt", "fake.png", "fat.pdf"] {
            #expect(WatchedPath.openable(box.path(name)) == box.root, "\(name) looks launchable")
        }
        try bytes("real.pdf", Array("%PDF-1.4".utf8))
        #expect(WatchedPath.openable(box.path("real.pdf")) == box.path("real.pdf"))
    }

    @Test func aLinkIsJudgedByWhereItLeads() throws {
        defer { box.cleanUp() }
        try bytes("tool", Array("#!/bin/sh\n".utf8), mode: 0o755)
        try box.write("real.pdf")
        let fm = FileManager.default
        try fm.createSymbolicLink(atPath: box.path("fine.pdf"), withDestinationPath: box.path("real.pdf"))
        try fm.createSymbolicLink(atPath: box.path("sneaky.pdf"), withDestinationPath: box.path("tool"))
        try fm.createSymbolicLink(atPath: box.path("nowhere.pdf"), withDestinationPath: box.path("missing"))
        #expect(WatchedPath.openable(box.path("fine.pdf")) == box.path("fine.pdf"))
        #expect(WatchedPath.openable(box.path("sneaky.pdf")) == box.root)
        #expect(WatchedPath.openable(box.path("nowhere.pdf")) == box.root)
    }

    @Test func foldersOpenUnlessTheyCouldBeProgramsAndMissingThingsShowTheirFolder() throws {
        defer { box.cleanUp() }
        for name in ["Project", "Thing.app", "Backup.v2", "Helper.xpc"] {
            try FileManager.default.createDirectory(atPath: box.path(name), withIntermediateDirectories: true)
        }
        #expect(WatchedPath.openable(box.path("Project")) == box.path("Project"))
        for name in ["Thing.app", "Backup.v2", "Helper.xpc"] { #expect(WatchedPath.openable(box.path(name)) == box.root, "\(name)") }
        #expect(WatchedPath.openable(box.path("gone.pdf")) == box.root)
    }

    @Test func theOpenButtonNeverLaunchesAnExtensionlessProgram() async throws {
        let env = try WatchEnv()
        defer { box.cleanUp() }
        try bytes("README", Array("#!/bin/sh\necho hi\n".utf8), mode: 0o755)
        let readme = box.path("README")
        let probe = ScriptedProbe { _, _ in
            ProbeResult(state: .object([:]), triggered: true, summary: "README arrived", openTarget: readme)
        }
        let engine = env.engine(probes: [probe])
        await engine.connectAttention()
        _ = try await engine.add(.make("fake", interval: 600, now: env.clock.now))
        await engine.tick()
        let notice = try #require(await env.notices().first { $0.title == "README arrived" })
        await env.attention.respond(id: notice.id, actionId: "open")
        #expect(env.openedURLs == [URL(fileURLWithPath: box.root)])
    }
}
