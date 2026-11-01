import Foundation
import GRDB
import Testing
@testable import SidefolkCore

/// Back up and restore (D91): a round trip between two data folders, what a restore refuses, the keys sealed with a
/// password, Undo restore, and a backup from an older Sidefolk migrated when it opens.
@Suite(.serialized) struct BackupTests {
    static func home(_ label: String) throws -> SidefolkPaths {
        SidefolkPaths(home: try ExtFixtures.tempDir("backup-\(label)"))
    }

    static func runtime(_ paths: SidefolkPaths) async throws -> SidefolkRuntime {
        try await SidefolkRuntime.open(paths: paths, platform: NullPlatform())
    }

    /// A data folder with notes, a reminder, an extension's own data, a skill and a companion made as data.
    static func filled(_ label: String) async throws -> (SidefolkPaths, SidefolkRuntime) {
        let paths = try home(label)
        let runtime = try await runtime(paths)
        let inbox = try await runtime.notebook.inbox()
        for text in ["Buy milk", "Call the dentist", "Ideas for the talk"] {
            try await runtime.notebook.add(NotebookItem(collectionId: inbox.id, kind: .note, title: text, body: "", source: "user"))
        }
        try await runtime.reminderStore.save(Reminder(title: "Stretch", fireAt: Date().addingTimeInterval(3600), timezone: "UTC", source: "user"))
        await runtime.settings.update { $0.companionName = "Biscuit" }
        try write("{\"kept\":312}", to: paths.extensionData.appendingPathComponent("dev.sidefolk.clipboard/state.json"))
        try write("---\nname: weekly\n---\nGather the week.\n", to: paths.skills.appendingPathComponent("weekly/SKILL.md"))
        try write("{}", to: paths.home.appendingPathComponent("companions/pebble/species.json"))
        return (paths, runtime)
    }

    static func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    static func titles(_ runtime: SidefolkRuntime) async throws -> [String] {
        try await runtime.db.writer.read { try NotebookItem.fetchAll($0).map(\.title).sorted() }
    }

    static func file(_ label: String) throws -> URL {
        try ExtFixtures.tempDir("backup-file").appendingPathComponent("\(label).\(BackupManifest.fileExtension)")
    }

    /// Restores `file` into `paths` as the app does: open and check, stage, then the swap at the next launch.
    static func restore(_ file: URL, into paths: SidefolkPaths) async throws -> BackupRestore.Outcome? {
        let backup = try await BackupReader.open(file)
        defer { backup.discard() }
        try BackupRestore(paths: paths).stage(backup)
        return BackupRestore(paths: paths).applyAtLaunch()
    }

    @Test func aBackupComesBackWholeInAnEmptyDataFolder() async throws {
        let (from, source) = try await Self.filled("from")
        let file = try Self.file("round")
        let manifest = try await BackupWriter(runtime: source).write(to: file, device: "Test Mac")
        #expect(manifest.counts.notes == 3 && manifest.counts.reminders == 1 && manifest.counts.skills == 1)
        #expect(!manifest.keys && manifest.files.keys.contains("data/sidefolk.sqlite"))
        #expect(!manifest.files.keys.contains { $0.contains("Logs") || $0.contains("Sandbox") || $0.contains("Addons") })
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)

        let to = try Self.home("to")
        guard case .restored(let plan)? = try await Self.restore(file, into: to) else { Issue.record("not restored"); return }
        #expect(plan.device == "Test Mac")
        let restored = try await Self.runtime(to)
        #expect(try await Self.titles(restored) == ["Buy milk", "Call the dentist", "Ideas for the talk"])
        #expect(try await restored.reminderStore.pending().map(\.title) == ["Stretch"])
        #expect(restored.settings.current.companionName == "Biscuit")
        for path in ["ExtensionData/dev.sidefolk.clipboard/state.json", "Skills/weekly/SKILL.md", "companions/pebble/species.json"] {
            #expect(FileManager.default.contents(atPath: to.home.appendingPathComponent(path).path)
                    == FileManager.default.contents(atPath: from.home.appendingPathComponent(path).path), "\(path)")
        }
        #expect(BackupRestore(paths: to).undoable != nil)
    }

    @Test func whatIsNotABackupOrDamagedIsRefusedAndNothingChanges() async throws {
        let junk = try Self.file("junk")
        try Data("not a zip at all".utf8).write(to: junk)
        await #expect(throws: UserFacingError.self) { _ = try await BackupReader.open(junk) }

        // A good backup with one file changed after it was made.
        let (_, source) = try await Self.filled("damaged")
        let file = try Self.file("good")
        try await BackupWriter(runtime: source).write(to: file)
        let unpacked = try ExtFixtures.tempDir("unpacked")
        _ = try await SystemTool.run("/usr/bin/ditto", ["-x", "-k", file.path, unpacked.path], timeout: 60)
        try Data("tampered".utf8).write(to: unpacked.appendingPathComponent("data/Skills/weekly/SKILL.md"))
        let tampered = try Self.file("tampered")
        _ = try await SystemTool.run("/usr/bin/ditto", ["-c", "-k", unpacked.path, tampered.path], timeout: 60)
        do {
            _ = try await BackupReader.open(tampered)
            Issue.record("a damaged backup opened")
        } catch let error as UserFacingError {
            #expect(error.message.contains("damaged"))
        }

        // A path that would leave the folder is refused before anything is unpacked.
        let escape = try Self.file("escape")
        let script = "import zipfile,sys\nz=zipfile.ZipFile(sys.argv[1],'w')\nz.writestr('manifest.json','{}')\nz.writestr('../outside.txt','x')\nz.close()"
        _ = try await SystemTool.run("/usr/bin/python3", ["-c", script, escape.path], timeout: 60)
        if FileManager.default.fileExists(atPath: escape.path) {
            await #expect(throws: UserFacingError.self) { _ = try await BackupReader.open(escape) }
            #expect(!FileManager.default.fileExists(atPath: FileManager.default.temporaryDirectory.appendingPathComponent("outside.txt").path))
        }
    }

    @Test func keysTravelOnlySealedWithThePassword() async throws {
        let (_, source) = try await Self.filled("keys")
        let store = InMemorySecretStore()
        try ProviderKeys(store: store).save(Secret("sk-ant-test-123"), account: SecretKey.anthropicAPIKey, host: ProviderKeys.anthropicHost)
        try store.set(SecretKey.mcpServer("mcp.github"), Secret("{\"GITHUB_TOKEN\":\"ghp_x\"}"))
        let keys = BackupKeys.collect(from: store, mcpServers: ["mcp.github"])
        #expect(keys.count == 3)
        let file = try Self.file("keys")
        let manifest = try await BackupWriter(runtime: source).write(to: file, keys: keys, password: "correct horse")
        #expect(manifest.keys)

        // Nowhere in the file in the clear.
        let unpacked = try ExtFixtures.tempDir("keys-unpacked")
        _ = try await SystemTool.run("/usr/bin/ditto", ["-x", "-k", file.path, unpacked.path], timeout: 60)
        let sealed = try Data(contentsOf: unpacked.appendingPathComponent("keys.json"))
        #expect(!String(decoding: sealed, as: UTF8.self).contains("sk-ant-test-123"))

        let backup = try await BackupReader.open(file)
        defer { backup.discard() }
        #expect(throws: UserFacingError.self) { _ = try backup.keys(password: "wrong horse") }
        let opened = try backup.keys(password: "correct horse")
        #expect(opened == keys)
        let other = InMemorySecretStore()
        try BackupKeys.save(opened.merging(["unrelated.item": "x"]) { a, _ in a }, to: other)
        #expect(try ProviderKeys(store: other).key(account: SecretKey.anthropicAPIKey, host: ProviderKeys.anthropicHost)?.reveal() == "sk-ant-test-123")
        #expect(try other.get("unrelated.item") == nil, "only names Sidefolk uses")
    }

    @Test func undoPutsBackWhatWasThereBefore() async throws {
        let (_, source) = try await Self.filled("undo-from")
        let file = try Self.file("undo")
        try await BackupWriter(runtime: source).write(to: file)

        // The app swaps only while nothing has the database open: here each look opens it and closes it again.
        func titles(_ paths: SidefolkPaths, adding title: String? = nil) async throws -> [String] {
            let db = try AppDatabase.open(at: paths.database)
            defer { try? (db.writer as? DatabasePool)?.close() }
            let notebook = NotebookStore(db)
            if let title {
                try await notebook.add(NotebookItem(collectionId: try await notebook.inbox().id, kind: .note, title: title, body: "", source: "user"))
            }
            return try await db.writer.read { try NotebookItem.fetchAll($0).map(\.title).sorted() }
        }
        let to = try Self.home("undo-to")
        try to.prepare()
        #expect(try await titles(to, adding: "Mine before") == ["Mine before"])
        _ = try await Self.restore(file, into: to)
        #expect(try await titles(to).contains("Buy milk"))

        try BackupRestore(paths: to).requestUndo()
        guard case .undone? = BackupRestore(paths: to).applyAtLaunch() else { Issue.record("not undone"); return }
        #expect(try await titles(to) == ["Mine before"])
        #expect(BackupRestore(paths: to).undoable == nil)
        #expect(throws: UserFacingError.self) { try BackupRestore(paths: to).requestUndo() }
    }

    @Test func anOlderDatabaseMigratesAndANewerOneIsRefused() async throws {
        // A backup from a Sidefolk that had only the first migration.
        func backup(_ label: String, change: @escaping @Sendable (Database) throws -> Void = { _ in }) async throws -> URL {
            let folder = try ExtFixtures.tempDir("old-\(label)")
            let data = folder.appendingPathComponent("data")
            try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
            let queue = try DatabaseQueue(path: data.appendingPathComponent("sidefolk.sqlite").path)
            try AppDatabase.migrator.migrate(queue, upTo: "v1")
            try await queue.write { db in
                try db.execute(sql: "INSERT INTO collections (id, name, kind, created_at, updated_at) VALUES ('c1', 'Inbox', 'inbox', 0, 0)")
                try db.execute(sql: """
                    INSERT INTO items (id, collection_id, kind, title, body, source, created_at, updated_at)
                    VALUES ('i1', 'c1', 'note', 'From an older Sidefolk', '', 'user', 0, 0)
                    """)
                try change(db)
            }
            try queue.close()
            let manifest = BackupManifest(format: 1, app: "0.1.0 snapshot 400", version: "0.1.0-snapshot.400", created: Date(),
                                          device: nil, schema: ["v1"], counts: .init(), extensions: [], addons: [], keys: false,
                                          files: try BackupFiles.digests(in: folder))
            try BackupManifest.encoder.encode(manifest).write(to: folder.appendingPathComponent(BackupManifest.fileName))
            let file = try Self.file(label)
            _ = try await SystemTool.run("/usr/bin/ditto", ["-c", "-k", folder.path, file.path], timeout: 60)
            return file
        }

        let to = try Self.home("old")
        _ = try await Self.restore(try await backup("older"), into: to)
        let runtime = try await Self.runtime(to)
        #expect(try await Self.titles(runtime).contains("From an older Sidefolk"))
        let applied = try await runtime.db.writer.read { try String.fetchAll($0, sql: "SELECT identifier FROM grdb_migrations") }
        #expect(Set(applied) == AppDatabase.migrationIdentifiers, "every migration ran on the restored database")

        let newer = try await backup("newer") { try $0.execute(sql: "INSERT INTO grdb_migrations (identifier) VALUES ('v99-future')") }
        do {
            _ = try await BackupReader.open(newer)
            Issue.record("a newer database opened")
        } catch let error as UserFacingError {
            #expect(error.message.contains("newer Sidefolk"))
        }
    }

    /// What is code from a folder waits for a look; MCP servers come back off; built-ins keep their switch.
    @Test(.enabled(if: ExtFixtures.hasPython, ExtFixtures.noPython))
    func extensionsFromAFolderWaitForALook() async throws {
        let (_, source) = try await Self.filled("ext")
        let folder = try ExtFixtures.makeExtension(at: try ExtFixtures.tempDir("src").appendingPathComponent("sample"),
                                                   manifest: ExtFixtures.manifest(id: "dev.test.sample"), files: ["server.py": ExtFixtures.server])
        _ = try await source.extensions.install(from: folder)
        let file = try Self.file("ext")
        let manifest = try await BackupWriter(runtime: source).write(to: file)
        #expect(manifest.extensions.map(\.source) == [.folder])
        #expect(manifest.files.keys.contains("review/extensions/dev.test.sample/server.py"))
        await source.extensions.shutdown()

        let to = try Self.home("ext-to")
        guard case .restored(let plan)? = try await Self.restore(file, into: to) else { Issue.record("not restored"); return }
        let restored = try await Self.runtime(to)
        #expect(await restored.extensions.extensions().isEmpty, "nothing from a folder runs before the person looks")
        let review = RestoreFollowUp(paths: to).toReview(plan: plan, installedExtensions: [], installedCompanions: [])
        #expect(review.map(\.id) == ["dev.test.sample"] && review.first?.name == "Sample")
        #expect(FileManager.default.fileExists(atPath: review[0].folder.appendingPathComponent("server.py").path))
    }
}
