import Foundation
import Testing
@testable import SidefolkCore

@Suite struct FileWriteToolTests {
    func paths(_ items: String...) -> JSONValue { .array(items.map { .string($0) }) }

    // MARK: move

    @Test func moveGoesToTheFolderAndUndoPutsItBack() async throws {
        let t = try BuiltinEnv()
        defer { t.cleanup() }
        try await t.grant()
        let a = try t.file("in/a.pdf", "A")
        let b = try t.file("in/b.pdf", "B")
        let dest = try t.folder("PDFs")

        let out = await t.run("files.move", ["paths": paths(a, b), "to_folder": .string(dest)], as: .user)
        let result = try #require(out.result)
        #expect(result.card?.title == "Moved 2 items")
        #expect(t.text(dest + "/a.pdf") == "A")
        #expect(t.text(dest + "/b.pdf") == "B")
        #expect(!t.exists(a))

        _ = try await t.env.executor.undo.undo(out.activity.id)
        #expect(t.text(a) == "A")
        #expect(t.text(b) == "B")
        #expect(!t.exists(dest + "/a.pdf"))
    }

    @Test func moveNeverOverwrites() async throws {
        let t = try BuiltinEnv()
        defer { t.cleanup() }
        try await t.grant()
        let incoming = try t.file("in/report.tar.gz", "new")
        let plain = try t.file("in/notes.txt", "new notes")
        let dest = try t.folder("out")
        try t.file("out/report.tar.gz", "old")
        try t.file("out/notes.txt", "old notes")
        try t.file("out/notes 2.txt", "older notes")

        let out = await t.run("files.move", ["paths": paths(incoming, plain), "to_folder": .string(dest)], as: .user)
        #expect(out.isOK)
        #expect(t.text(dest + "/report.tar.gz") == "old")
        #expect(t.text(dest + "/report 2.tar.gz") == "new")
        #expect(t.text(dest + "/notes.txt") == "old notes")
        #expect(t.text(dest + "/notes 2.txt") == "older notes")
        #expect(t.text(dest + "/notes 3.txt") == "new notes")
        #expect(out.result?.text.contains("became") == true)
    }

    @Test func moveRefusesBadDestinationsAndSources() async throws {
        let t = try BuiltinEnv()
        defer { t.cleanup() }
        try await t.grant()
        let file = try t.file("a.txt", "A")
        let folder = try t.folder("dir")
        try t.file("dir/inner/x.txt", "X")

        let missingDest = await t.run("files.move", ["paths": paths(file), "to_folder": .string(t.root + "/nowhere")], as: .user)
        #expect(missingDest.failure?.recovery?.contains("files.mkdir") == true)
        let toFile = await t.run("files.move", ["paths": paths(folder), "to_folder": .string(file)], as: .user)
        #expect(toFile.failure != nil)
        let intoSelf = await t.run("files.move", ["paths": paths(folder), "to_folder": .string(folder + "/inner")], as: .user)
        #expect(intoSelf.failure != nil)
        let missingSource = await t.run("files.move", ["paths": paths(file, t.root + "/ghost.txt"), "to_folder": .string(folder)], as: .user)
        #expect(missingSource.failure != nil)
        #expect(t.exists(file))   // a bad entry fails the whole call before anything moves
        #expect(await t.run("files.move", ["paths": paths(), "to_folder": .string(folder)], as: .user).failure != nil)
    }

    @Test func moveSourceOutsideGrantAsksAndWritesNeedReadWrite() async throws {
        let t = try BuiltinEnv()
        defer { t.cleanup() }
        let shared = try t.folder("shared")
        let other = try t.file("other/x.txt", "X")
        try await t.grant(shared)

        let answer = t.env.autoAnswer(.deny)
        let out = await t.run("files.move", ["paths": paths(other), "to_folder": .string(shared)], as: .user)
        let asked = try #require(await answer.value)
        guard case .folderAccess(_, let write) = asked.details else { Issue.record("expected a folder request"); return }
        #expect(write)
        #expect(out.wasDenied)
        #expect(t.exists(other))

        // A read-only grant is not enough to change files.
        let readOnly = try t.folder("readonly")
        try await t.env.permissions.grantFolder(readOnly, access: .read)
        let file = try t.file("readonly/r.txt")
        let answer2 = t.env.autoAnswer(.deny)
        let denied = await t.run("files.rename", ["path": .string(file), "new_name": "s.txt"], as: .user)
        _ = await answer2.value
        #expect(denied.wasDenied)
        #expect(t.exists(file))
    }

    @Test func agentMovesNeedApprovalEachTimeUnlessGranted() async throws {
        let t = try BuiltinEnv()
        defer { t.cleanup() }
        try await t.grant()
        let file = try t.file("a.txt")
        let dest = try t.folder("dest")
        let answer = t.env.autoAnswer(.deny)
        let denied = await t.run("files.move", ["paths": paths(file), "to_folder": .string(dest)])
        let asked = try #require(await answer.value)
        #expect(asked.risk == .medium)
        // The test runner has no string catalog, so a count reads as its key; CatalogTests checks the English singular.
        #expect(asked.summary == "Move 1 items to \(dest)")
        #expect(denied.wasDenied)
        #expect(t.exists(file))
        let yes = t.env.autoAnswer(.allowOnce)
        #expect(await t.run("files.move", ["paths": paths(file), "to_folder": .string(dest)]).isOK)
        _ = await yes.value
    }

    // MARK: rename

    @Test func renameWorksAndUndoes() async throws {
        let t = try BuiltinEnv()
        defer { t.cleanup() }
        try await t.grant()
        let path = try t.file("old.txt", "content")
        let out = await t.run("files.rename", ["path": .string(path), "new_name": "New Name.txt"], as: .user)
        #expect(out.isOK)
        #expect(t.text(t.root + "/New Name.txt") == "content")
        #expect(!t.exists(path))
        _ = try await t.env.executor.undo.undo(out.activity.id)
        #expect(t.text(path) == "content")
    }

    @Test func renameNeverReplacesAndRejectsOddNames() async throws {
        let t = try BuiltinEnv()
        defer { t.cleanup() }
        try await t.grant()
        let a = try t.file("a.txt", "A")
        let b = try t.file("b.txt", "B")
        let clash = await t.run("files.rename", ["path": .string(a), "new_name": "b.txt"], as: .user)
        #expect(clash.failure?.message.contains("already something called") == true)
        #expect(t.text(b) == "B")

        for name in ["../escape.txt", "sub/dir.txt", ".hidden", "..", "run.command", "Evil.app", "a.txt"] {
            let out = await t.run("files.rename", ["path": .string(a), "new_name": .string(name)], as: .user)
            #expect(out.failure != nil || out.wasDenied, "rename to \(name) must fail")
        }
        #expect(t.text(a) == "A")
        #expect(!t.exists(t.root + "/escape.txt"))
    }

    @Test func renamingAScriptKeepsItsKindButCannotBecomeOne() async throws {
        let t = try BuiltinEnv()
        defer { t.cleanup() }
        try await t.grant()
        let script = try t.file("tool.command", "#!/bin/sh")
        #expect(await t.run("files.rename", ["path": .string(script), "new_name": "other.command"], as: .user).isOK)
        let text = try t.file("notes.txt")
        #expect(await t.run("files.rename", ["path": .string(text), "new_name": "notes.workflow"], as: .user).failure != nil)
    }

    @Test func caseOnlyRenameIsAllowed() async throws {
        let t = try BuiltinEnv()
        defer { t.cleanup() }
        try await t.grant()
        let path = try t.file("readme.txt", "R")
        let out = await t.run("files.rename", ["path": .string(path), "new_name": "README.txt"], as: .user)
        #expect(out.isOK)
        let names = try FileManager.default.contentsOfDirectory(atPath: t.root).filter { !$0.hasPrefix(".") }
        #expect(names.contains("README.txt"))
    }

    @Test func linksAndTopLevelHomeFoldersAreNotRenamedMovedOrTrashed() async throws {
        let t = try BuiltinEnv()
        defer { t.cleanup() }
        try await t.grant()
        let real = try t.file("real.txt")
        let link = t.root + "/shortcut"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: real)
        #expect(await t.run("files.rename", ["path": .string(link), "new_name": "x"], as: .user).failure != nil)
        #expect(await t.run("files.trash", ["paths": paths(link)], as: .user).failure != nil)
        #expect(t.exists(real))

        let home = FolderAccess.canonical(NSHomeDirectory())!
        #expect(FilePaths.isHomeTopLevel(home))
        #expect(FilePaths.isHomeTopLevel(home + "/Documents"))
        #expect(!FilePaths.isHomeTopLevel(home + "/Documents/Taxes"))
    }

    // MARK: mkdir

    @Test func mkdirCreatesNestedFoldersAndUndoRemovesOnlyEmptyOnes() async throws {
        let t = try BuiltinEnv()
        defer { t.cleanup() }
        try await t.grant()
        let deep = t.root + "/Invoices/2025/Q1"
        let out = await t.run("files.mkdir", ["path": .string(deep)], as: .user)
        #expect(out.isOK)
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: deep, isDirectory: &isDir) && isDir.boolValue)

        // Something lands in the new folder: undo must not touch it.
        try t.file("Invoices/2025/Q1/keep.txt")
        await #expect(throws: UserFacingError.self) { _ = try await t.env.executor.undo.undo(out.activity.id) }
        #expect(t.exists(deep + "/keep.txt"))

        let fresh = await t.run("files.mkdir", ["path": .string(t.root + "/Empty/Child")], as: .user)
        _ = try await t.env.executor.undo.undo(fresh.activity.id)
        #expect(!t.exists(t.root + "/Empty"))
    }

    @Test func mkdirIsIdempotentAndRefusesFilesHiddenAndRiskyNames() async throws {
        let t = try BuiltinEnv()
        defer { t.cleanup() }
        try await t.grant()
        let existing = try t.folder("there")
        let again = await t.run("files.mkdir", ["path": .string(existing)], as: .user)
        #expect(again.result?.text.contains("already exists") == true)
        #expect(!again.activity.undoAvailable)
        let file = try t.file("file.txt")
        #expect(await t.run("files.mkdir", ["path": .string(file)], as: .user).failure != nil)
        #expect(await t.run("files.mkdir", ["path": .string(t.root + "/Tool.app")], as: .user).failure != nil)
        #expect(await t.run("files.mkdir", ["path": .string(t.root + "/.config")], as: .user).wasDenied)
        #expect(!t.exists(t.root + "/Tool.app"))
    }

    @Test func mkdirThroughADanglingLinkDoesNotCreateTheOutsideTarget() async throws {
        let t = try BuiltinEnv()
        defer { t.cleanup() }
        let granted = try t.folder("granted")
        let outside = try t.folder("outside")
        try await t.grant(granted)
        let target = outside + "/created-by-attack"
        try FileManager.default.createSymbolicLink(atPath: granted + "/dangling", withDestinationPath: target)
        let out = await t.run("files.mkdir", ["path": .string(granted + "/dangling")], as: .user)
        #expect(out.result == nil)
        #expect(!t.exists(target))
        let nested = await t.run("files.mkdir", ["path": .string(granted + "/dangling/sub")], as: .user)
        #expect(nested.result == nil)
        #expect(!t.exists(target))
    }

    // MARK: trash

    @Test func trashIsHighRiskAndUndoPutsItemsBack() async throws {
        let t = try BuiltinEnv()
        defer { t.cleanup() }
        try await t.grant()
        let a = try t.file("a.txt", "A")
        let dir = try t.folder("dir")
        try t.file("dir/inner.txt", "I")
        #expect(t.env.registry.tool(named: "files.trash")?.spec.risk == .high)

        // An agent always has to ask, and "always allow" is not offered for high risk.
        let answer = t.env.autoAnswer(.deny)
        let denied = await t.run("files.trash", ["paths": paths(a)])
        let asked = try #require(await answer.value)
        #expect(asked.risk == .high)
        #expect(!asked.canAlways)
        #expect(denied.wasDenied)
        #expect(t.exists(a))

        let yes = t.env.autoAnswer(.allowOnce)
        let out = await t.run("files.trash", ["paths": paths(a, dir)])
        _ = await yes.value
        let result = try #require(out.result)
        #expect(result.card?.title == "Moved 2 items to the Trash")
        #expect(!t.exists(a))
        #expect(!t.exists(dir))

        _ = try await t.env.executor.undo.undo(out.activity.id)
        #expect(t.text(a) == "A")
        #expect(t.text(dir + "/inner.txt") == "I")
    }

    @Test func trashUndoDoesNotReplaceANewFileAtTheOldPath() async throws {
        let t = try BuiltinEnv()
        defer { t.cleanup() }
        try await t.grant()
        let a = try t.file("a.txt", "original")
        let out = await t.run("files.trash", ["paths": paths(a)], as: .user)
        try t.file("a.txt", "someone made a new one")
        await #expect(throws: UserFacingError.self) { _ = try await t.env.executor.undo.undo(out.activity.id) }
        #expect(t.text(a) == "someone made a new one")
    }

    @Test func trashOutsideTheGrantedFolderIsStoppedByGuard() async throws {
        let t = try BuiltinEnv()
        defer { t.cleanup() }
        let shared = try t.folder("shared")
        let precious = try t.file("precious/photo.jpg", "P")
        try await t.grant(shared)
        let answer = t.env.autoAnswer(.deny)
        let out = await t.run("files.trash", ["paths": paths(precious)], as: .user)
        _ = await answer.value
        #expect(out.wasDenied)
        #expect(t.exists(precious))
    }

    // Puts one uniquely named temp file in the real Trash, so it only runs on request.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SIDEFOLK_TEST_REAL_TRASH"] == "1"))
    func realTrashWorksWhenAsked() async throws {
        let t = try BuiltinEnv()
        defer { t.cleanup() }
        try await t.grant()
        let path = try t.file("sidefolk-test-\(UUID().uuidString).txt", "bye")
        let trashed = try SystemTrash().trash(path: path)
        #expect(!t.exists(path))
        #expect(t.exists(trashed))
        try? FileManager.default.removeItem(atPath: trashed)
    }
}

@Suite struct FilePathsTests {
    @Test func namesMustBePlainNames() throws {
        #expect(try FilePaths.validateName("  Report 2025.pdf ") == "Report 2025.pdf")
        for bad in ["", "a/b", "..", ".", ".env", "x\u{0}y", "line\nbreak", String(repeating: "a", count: 300)] {
            #expect(throws: (any Error).self) { try FilePaths.validateName(bad) }
        }
    }

    @Test func scopePathsAreCanonicalOrNil() throws {
        let t = try BuiltinEnv()
        defer { t.cleanup() }
        #expect(FilePaths.scopePath(t.root + "/x/../y") == nil)
        #expect(FilePaths.scopePath("relative.txt") == nil)
        #expect(FilePaths.scopePath("  ") == nil)
        #expect(FilePaths.scopePath(nil) == nil)
        #expect(FilePaths.scopePath("/tmp/sidefolk-x") == "/private/tmp/sidefolk-x")
    }

    @Test func riskyTypesAndUniqueNames() {
        #expect(FilePaths.isRisky(name: "x.COMMAND"))
        #expect(FilePaths.isRisky(name: "Thing.app"))
        #expect(!FilePaths.isRisky(name: "notes.txt"))
        #expect(FileNames.candidates(for: "a.tar.gz", limit: 3) == ["a.tar.gz", "a 2.tar.gz", "a 3.tar.gz"])
        #expect(FileNames.candidates(for: "Makefile", limit: 2) == ["Makefile", "Makefile 2"])
        #expect(FileNames.candidates(for: "photo.JPG", limit: 2) == ["photo.JPG", "photo 2.JPG"])
    }
}
