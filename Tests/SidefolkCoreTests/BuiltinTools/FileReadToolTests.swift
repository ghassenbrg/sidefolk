import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import SidefolkCore

/// A one-page PDF with `text` drawn on it.
func makePDF(_ text: String) -> Data {
    let data = NSMutableData()
    var box = CGRect(x: 0, y: 0, width: 612, height: 792)
    let context = CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: &box, nil)!
    context.beginPDFPage(nil)
    let font = CTFontCreateWithName("Helvetica" as CFString, 24, nil)
    let attributed = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
    context.textPosition = CGPoint(x: 72, y: 700)
    CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
    context.endPDFPage()
    context.closePDF()
    return data as Data
}

@Suite struct FileReadToolTests {
    @Test func listShowsNamesSizesAndHidesDotfiles() async throws {
        let t = try BuiltinEnv()
        defer { t.cleanup() }
        try await t.grant()
        try t.file("docs/b.txt", "bee")
        try t.file("docs/A.pdf", "pdf")
        try t.file("docs/.secret", "x")
        try t.folder("docs/sub")

        let out = await t.run("files.list", ["path": .string(t.root + "/docs")])
        let result = try #require(out.result)
        let lines = result.text.split(separator: "\n").map(String.init)
        #expect(lines[0].hasPrefix("3 items in"))
        // Folders first, then names in natural order.
        #expect(lines[1].hasPrefix("sub/ — folder"))
        #expect(lines[2].hasPrefix("A.pdf — "))
        #expect(lines[3].hasPrefix("b.txt — 3 bytes, TXT file, modified "))
        #expect(!result.text.contains(".secret"))
        #expect(result.untrusted)   // file names come from outside

        let filtered = await t.run("files.list", ["path": .string(t.root + "/docs"), "pattern": "*.PDF"])
        #expect(filtered.result?.text.contains("A.pdf") == true)
        #expect(filtered.result?.text.contains("b.txt") == false)
        let plain = await t.run("files.list", ["path": .string(t.root + "/docs"), "pattern": "b.t"])
        #expect(plain.result?.text.contains("b.txt") == true)
        #expect(plain.result?.text.contains("A.pdf") == false)
        let limited = await t.run("files.list", ["path": .string(t.root + "/docs"), "limit": 1])
        #expect(limited.result?.text.contains("and 2 more") == true)
        #expect(await t.run("files.list", ["path": .string(t.root + "/docs/b.txt")]).failure != nil)
        #expect(await t.run("files.list", ["path": .string(t.root + "/missing")]).failure != nil)
    }

    @Test func listingOutsideGrantedFoldersAsksFirst() async throws {
        let t = try BuiltinEnv()
        defer { t.cleanup() }
        try t.file("private/x.txt")
        let answer = t.env.autoAnswer(.deny)
        let out = await t.run("files.list", ["path": .string(t.root + "/private")])
        let asked = try #require(await answer.value)
        guard case .folderAccess(let folder, let write) = asked.details else { Issue.record("expected a folder request"); return }
        #expect(folder == t.root + "/private")
        #expect(!write)
        #expect(out.wasDenied)

        // Once the user says yes, the call goes through.
        let yes = t.env.autoAnswer(.allowOnce)
        let again = await t.run("files.list", ["path": .string(t.root + "/private")])
        _ = await yes.value
        #expect(again.isOK)
    }

    @Test func readReturnsUntrustedTextWithTheHeaderLine() async throws {
        let t = try BuiltinEnv()
        defer { t.cleanup() }
        try await t.grant()
        let path = try t.file("notes.txt", "Line one\nHidden\u{202E}text\nLine three")
        let out = await t.run("files.read", ["path": .string(path)])
        let result = try #require(out.result)
        #expect(result.untrusted)
        #expect(result.text.hasPrefix("File: "))
        #expect(result.text.contains("Line one\nHiddentext\nLine three"))   // bidi control stripped
        #expect(result.card?.title == "notes.txt")
        #expect(out.modelText.hasPrefix("<untrusted_content>"))
    }

    @Test func readCapsLongFilesAndSaysSo() async throws {
        let t = try BuiltinEnv()
        defer { t.cleanup() }
        try await t.grant()
        let path = try t.file("big.txt", String(repeating: "abcdefghij", count: 6_000))   // 60k characters
        let out = await t.run("files.read", ["path": .string(path)])
        let text = try #require(out.result).text
        #expect(text.contains("Showing the first 30,000 characters"))
        #expect(text.count < 30_400)
        let small = await t.run("files.read", ["path": .string(path), "max_chars": 500])
        #expect(small.result?.text.contains("first 500 characters") == true)
    }

    @Test func readRefusesBinaryFoldersAndEmptyPaths() async throws {
        let t = try BuiltinEnv()
        defer { t.cleanup() }
        try await t.grant()
        let bin = t.root + "/pic.png"
        try Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0x00, 0x1A, 0x0A, 0x00, 0xFF, 0xD8]).write(to: URL(fileURLWithPath: bin))
        let out = await t.run("files.read", ["path": .string(bin)])
        #expect(out.failure?.message.contains("binary") == true)
        let dir = try t.folder("dir")
        #expect(await t.run("files.read", ["path": .string(dir)]).failure != nil)
        #expect(await t.run("files.read", ["path": .string(t.root + "/nope.txt")]).failure != nil)
        let empty = try t.file("empty.txt", "")
        #expect(await t.run("files.read", ["path": .string(empty)]).result?.text.contains("empty") == true)
    }

    @Test func readDecodesLegacyEncodings() async throws {
        let t = try BuiltinEnv()
        defer { t.cleanup() }
        try await t.grant()
        let path = t.root + "/latin.txt"
        try Data("café au lait".data(using: .isoLatin1)!).write(to: URL(fileURLWithPath: path))
        #expect(await t.run("files.read", ["path": .string(path)]).result?.text.contains("café au lait") == true)
    }

    @Test func readExtractsTextFromPDFs() async throws {
        let t = try BuiltinEnv()
        defer { t.cleanup() }
        try await t.grant()
        let path = t.root + "/report.pdf"
        try makePDF("Quarterly report seven").write(to: URL(fileURLWithPath: path))
        let out = await t.run("files.read", ["path": .string(path)])
        let result = try #require(out.result)
        #expect(result.text.contains("Quarterly report seven"))
        #expect(result.card?.subtitle?.contains("PDF, 1 page") == true)
        #expect(result.untrusted)

        let broken = t.root + "/broken.pdf"
        try Data("%PDF-1.4 this is not really a pdf".utf8).write(to: URL(fileURLWithPath: broken))
        #expect(await t.run("files.read", ["path": .string(broken)]).failure != nil)
    }

    @Test func hiddenAndProtectedPathsAreBlockedForEveryone() async throws {
        let t = try BuiltinEnv()
        defer { t.cleanup() }
        try await t.grant()
        let env = try t.file(".env", "API_KEY=abc")
        let nested = try t.file(".git/config", "[core]")
        for caller in [Caller.user, .agent(runId: "r")] {
            for path in [env, nested, NSHomeDirectory() + "/.ssh/id_rsa", NSHomeDirectory() + "/Library/Keychains/login.keychain-db"] {
                let out = await t.run("files.read", ["path": .string(path)], as: caller)
                #expect(out.wasDenied, "\(path) should be blocked")
            }
        }
    }

    @Test func symlinksCannotSmuggleReadsOutOfAGrantedFolder() async throws {
        let t = try BuiltinEnv()
        defer { t.cleanup() }
        let granted = try t.folder("granted")
        let outside = try t.folder("outside")
        try t.file("outside/secret.txt", "top secret")
        try await t.grant(granted)
        try FileManager.default.createSymbolicLink(atPath: granted + "/link", withDestinationPath: outside)
        try FileManager.default.createSymbolicLink(atPath: granted + "/filelink", withDestinationPath: outside + "/secret.txt")

        let answer = t.env.autoAnswer(.deny)
        let viaFolder = await t.run("files.read", ["path": .string(granted + "/link/secret.txt")], as: .user)
        let asked = await answer.value
        #expect(viaFolder.wasDenied)
        guard case .folderAccess(let folder, _)? = asked?.details else { Issue.record("expected a folder request"); return }
        #expect(folder == outside)   // Guard judged the real location, not the link's spelling

        let answer2 = t.env.autoAnswer(.deny)
        let viaFile = await t.run("files.read", ["path": .string(granted + "/filelink")], as: .user)
        _ = await answer2.value
        #expect(viaFile.wasDenied)
    }

    @Test func traversalAndRelativePathsAreRefused() async throws {
        let t = try BuiltinEnv()
        defer { t.cleanup() }
        try await t.grant(try t.folder("granted"))
        try t.file("outside.txt", "nope")
        for path in [t.root + "/granted/../outside.txt", "outside.txt", "./outside.txt", "~/../etc/passwd"] {
            let out = await t.run("files.read", ["path": .string(path)], as: .user)
            #expect(out.failure != nil || out.wasDenied, "\(path) must not be read")
            #expect(out.result == nil)
        }
    }

    @Test func revealShowsTheItemInFinder() async throws {
        let t = try BuiltinEnv()
        defer { t.cleanup() }
        try await t.grant()
        let path = try t.file("shown.txt")
        #expect(await t.run("files.reveal", ["path": .string(path)]).isOK)
        #expect(t.platform.revealed == [path])
        #expect(await t.run("files.reveal", ["path": .string(t.root + "/gone.txt")]).failure != nil)
    }
}

@Suite struct FileSearchToolTests {
    @Test func resultsAreFilteredToTheFolderAndLeaveOutHiddenAndEscapes() async throws {
        let t = try BuiltinEnv()
        defer { t.cleanup() }
        let docs = try t.folder("docs")
        let inside = try t.file("docs/invoice 2025.pdf", "pdf")
        let nested = try t.file("docs/sub/invoice b.txt", "b")
        let hidden = try t.file("docs/.hidden/invoice.txt", "h")
        let elsewhere = try t.file("other/invoice.txt", "o")
        try FileManager.default.createSymbolicLink(atPath: docs + "/escape", withDestinationPath: t.root + "/other")
        let search = FilesSearchTool(searcher: FakeSearch(results: [inside, hidden, elsewhere, docs + "/escape/invoice.txt", nested, docs + "/../other/invoice.txt"]))
        t.env.registry.register(search)
        try await t.grant(docs)

        let out = await t.run("files.search", ["query": "invoice", "folder": .string(docs)])
        let result = try #require(out.result)
        #expect(result.text.contains("2 files"))
        #expect(result.text.contains("invoice 2025.pdf"))
        #expect(result.text.contains("invoice b.txt"))
        #expect(!result.text.contains("hidden"))
        #expect(!result.text.contains("other/"))
        #expect(result.untrusted)
    }

    @Test func folderMustBeSharedAndQueryCannotBeAnOption() async throws {
        let t = try BuiltinEnv()
        defer { t.cleanup() }
        let docs = try t.folder("docs")
        let answer = t.env.autoAnswer(.deny)
        let out = await t.run("files.search", ["query": "x", "folder": .string(docs)])
        _ = await answer.value
        #expect(out.wasDenied)

        try await t.grant(docs)
        #expect(await t.run("files.search", ["query": "-live", "folder": .string(docs)]).failure != nil)
        #expect(await t.run("files.search", ["query": "nothing", "folder": .string(docs)]).result?.text.contains("Nothing") == true)
        #expect(await t.run("files.search", ["query": "x", "folder": .string(docs + "/none")]).failure != nil)
    }

    @Test func spotlightPlumbingWorksOnAnEmptyFolder() async throws {
        let t = try BuiltinEnv()
        defer { t.cleanup() }
        let docs = try t.folder("docs")
        // Real /usr/bin/mdfind: an empty temp folder yields no results, quickly and without hanging.
        let found = try await SpotlightSearch().search(query: "zzqqxxunlikelyname", inFolder: docs, limit: 10)
        #expect(found.isEmpty)
    }

    @Test func spotlightTimeoutIsReportedPlainly() async throws {
        let t = try BuiltinEnv()
        defer { t.cleanup() }
        let docs = try t.folder("docs")
        await #expect(throws: UserFacingError.self) {
            _ = try await SpotlightSearch(timeout: 0.0001).search(query: "anything", inFolder: docs, limit: 10)
        }
    }
}
