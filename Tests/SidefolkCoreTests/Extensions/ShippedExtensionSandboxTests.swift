import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Metal
import Testing
import UniformTypeIdentifiers
@testable import SidefolkCore

/// Every extension that ships with Sidefolk, installed from its built program and called through the executor, so it
/// runs under the same sandbox as in the app: proof that each one works with nothing installed on the Mac.
struct ShippedExtensionSandboxTests {
    /// Core Image needs a real Apple GPU in the sandbox; a virtual machine's (CI) isn't one of the two it opens.
    static let appleGPU = MTLCreateSystemDefaultDevice().map { $0.name.hasPrefix("Apple") && !$0.name.contains("Paravirtual") } ?? false

    /// A folder shared with Sidefolk, as the person would share it.
    static func sharedFolder(_ h: HostEnv) async throws -> URL {
        let work = h.root.appendingPathComponent("work", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try await h.env.permissions.grantFolder(work.path, access: .readwrite)
        return URL(fileURLWithPath: FolderAccess.canonical(work.path)!, isDirectory: true)
    }

    static func png(_ url: URL, width: Int = 320, height: Int = 200) throws {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 0.2, green: 0.6, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let out = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(out, context.makeImage()!, nil)
        #expect(CGImageDestinationFinalize(out))
    }

    /// A PDF with one line of text on each page.
    static func pdf(_ url: URL, lines: [String]) {
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        let context = CGContext(url as CFURL, mediaBox: &box, nil)!
        for line in lines {
            context.beginPDFPage(nil)
            let text = CTLineCreateWithAttributedString(NSAttributedString(string: line, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 24, nil),
            ]))
            context.textPosition = CGPoint(x: 72, y: 700)
            CTLineDraw(text, context)
            context.endPDFPage()
        }
        context.closePDF()
    }

    @Test func systemVitalsRunsInTheSandbox() async throws {
        let h = try HostEnv()
        let info = try await h.host.install(from: ExtFixtures.builtIn("system-vitals"))
        #expect(info.tools.map(\.name) == ["ext.system-vitals.about", "ext.system-vitals.battery", "ext.system-vitals.disk",
                                           "ext.system-vitals.memory"])
        #expect(info.tools.allSatisfy { $0.risk == .low && !$0.quarantined })
        #expect(info.watchers.map(\.watcher) == ["battery_low", "disk_low"])

        let battery = await h.call("ext.system-vitals.battery")
        let text = try #require(battery.okText, "\(String(describing: battery.failure))")
        #expect(text.hasPrefix("Battery at") || text.hasPrefix("This Mac has no battery"), "\(text)")
        #expect(battery.untrusted)
        let disk = try #require(await h.call("ext.system-vitals.disk").okText)
        #expect(disk.contains("GB free of"), "\(disk)")
        let memory = try #require(await h.call("ext.system-vitals.memory").okText)
        #expect(memory.contains("memory pressure is") && !memory.contains("unknown"), "\(memory)")
        let about = try #require(await h.call("ext.system-vitals.about").okText)
        #expect(about.hasPrefix("This Mac: ") && about.contains("GB of memory") && about.contains("macOS "), "\(about)")

        // The startup disk always has more than 0.5 GB free here, and less than a petabyte.
        let low = try await h.host.checkWatcher(extensionId: info.id, watcher: "disk_low", config: ["below_gb": 1_000_000], state: .null)
        #expect(low.triggered && low.state == ["low": true])
        let again = try await h.host.checkWatcher(extensionId: info.id, watcher: "disk_low", config: ["below_gb": 1_000_000], state: low.state)
        #expect(!again.triggered)
        await h.host.shutdown()
    }

    @Test(.enabled(if: ExtFixtures.hasAddons, ExtFixtures.noAddons))
    func calculatorPlaytimeAndDevToolboxNeedNoPermission() async throws {
        let h = try HostEnv()
        for folder in ["calculator", "playtime", "dev-toolbox"] {
            let info = try await h.host.install(from: ExtFixtures.builtIn(folder))
            #expect(info.summary.texts.first == "No access to your files or the internet" || folder == "dev-toolbox", "\(folder)")
        }
        #expect(await h.call("ext.calculator.calculate", ["expression": "(12.5 * 4) + 15%"]).okText == "(12.5 * 4) + 15% = 57.5")
        #expect(await h.call("ext.calculator.convert_units", ["value": 100, "from": "°F", "to": "celsius"]).okText == "100 °F = 37.7778 °C")
        let date = try #require(await h.call("ext.calculator.date_math", ["date": "2026-12-24", "to": "2027-01-04"]).okText)
        #expect(date.contains("11 days"), "\(date)")

        let picked = try #require(await h.call("ext.playtime.pick", ["kind": "choice", "choices": ["tea", "coffee"]]).okText)
        #expect(picked == "Picked: tea." || picked == "Picked: coffee.")
        // The quiz keeps its question and score in its own data folder, between two calls (two processes).
        let question = try #require(await h.call("ext.playtime.trivia", ["category": "space"]).okText)
        #expect(question.hasPrefix("Question (space):") && question.contains("A) ") && question.contains("D) "), "\(question)")
        let graded = try #require(await h.call("ext.playtime.trivia", ["answer": "A"]).okText)
        #expect(graded.contains("Score: ") && graded.contains("of 1") && graded.contains("Question (space):"), "\(graded)")

        #expect(await h.call("ext.dev-toolbox.transform", ["operation": "sha256", "text": "abc"]).okText
            == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        let work = try await Self.sharedFolder(h)
        try Data("hello\n".utf8).write(to: work.appendingPathComponent("hello.txt"))
        let sum = try #require(await h.call("ext.dev-toolbox.checksum", ["path": .string(work.appendingPathComponent("hello.txt").path)]).okText)
        #expect(sum.hasSuffix("5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03"), "\(sum)")
        await h.host.shutdown()
    }

    /// Trivia in the Play panel (D75), played over the game channel inside the sandbox: German words, the companion's
    /// sealed pick, an answer, and its page in Home.
    @Test(.enabled(if: ExtFixtures.hasAddons, ExtFixtures.noAddons))
    func playtimeTriviaIsPlayedOverTheGameChannel() async throws {
        let h = try HostEnv()
        let info = try await h.host.install(from: ExtFixtures.builtIn("playtime"))
        #expect(h.host.gameShelf.all.map(\.id).contains("\(info.id)/trivia") && h.host.gameShelf.all.count == 11)
        let (session, setup) = try await h.host.startGame(extensionId: info.id, game: "trivia",
                                                          setup: GameSetup(language: "de", options: ["companion": "Nori"]))
        guard case .prompt(let p) = setup.parts.first else { Issue.record("\(setup.parts)"); return }
        #expect(p.eyebrow == "Ein Quiz mit Nori" && setup.primary?.label == "Starten" && setup.cue?.line == .hello)
        let question = try await h.host.moveGame(extensionId: info.id, game: "trivia", session: session, move: .button("start"))
        #expect(question.score?.companionPicked == true && question.answers?.tiles.count == 4 && question.answers?.locked == false)
        let answered = try await h.host.moveGame(extensionId: info.id, game: "trivia", session: session, move: .answer(1))
        #expect(answered.answers?.locked == true && answered.answers?.tiles.filter(\.companion).count == 1 && answered.primary?.move == "next")
        await h.host.endGame(extensionId: info.id, game: "trivia", session: session, reason: .closed)
        let page = try await h.host.renderPage(extensionId: info.id, page: "playtime", language: "fr")
        #expect(page.hero?.eyebrow == "Récré", "Playtime's page in French")
        await h.host.shutdown()
    }

    @Test(.enabled(if: ExtFixtures.hasAddons, ExtFixtures.noAddons))
    func imagesConvertIntoTheFolderNamedOnly() async throws {
        let h = try HostEnv()
        let info = try await h.host.install(from: ExtFixtures.builtIn("images"))
        #expect(info.summary.texts.contains("Can use the Mac's graphics hardware for pictures"))
        let work = try await Self.sharedFolder(h)
        try Self.png(work.appendingPathComponent("sky.png"))
        let details = try #require(await h.call("ext.images.image_info", ["path": .string(work.appendingPathComponent("sky.png").path)]).okText)
        #expect(details.hasPrefix("sky.png: 320 × 200 px") && details.contains("no location"), "\(details)")
        let made = try #require(await h.call("ext.images.convert_images", ["folder": .string(work.path), "format": "jpeg", "max_size": 100,
                                                                         "remove_location": true]).okText)
        #expect(made.hasPrefix("Made 1 copy in ") && made.contains("at most 100 px"), "\(made)")
        let copy = work.appendingPathComponent("Converted/sky.jpg")
        let source = try #require(CGImageSourceCreateWithURL(copy as CFURL, nil))
        let props = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(props[kCGImagePropertyPixelWidth] as? Int == 100)
        #expect(FileManager.default.fileExists(atPath: work.appendingPathComponent("sky.png").path), "the original stays")
        await h.host.shutdown()
    }

    @Test(.enabled(if: ExtFixtures.hasAddons, ExtFixtures.noAddons),
          .enabled(if: appleGPU, "Core Image needs an Apple GPU (not a virtual machine's)"))
    func qrCodesAreMadeAndReadInTheSandbox() async throws {
        let h = try HostEnv()
        try await h.host.install(from: ExtFixtures.builtIn("qr-codes"))
        let work = try await Self.sharedFolder(h)
        let made = try #require(await h.call("ext.qr-codes.make_qr", ["text": "https://sidefolk.app", "folder": .string(work.path),
                                                                    "name": "site"]).okText)
        #expect(made.contains("site.png"), "\(made)")
        let read = await h.call("ext.qr-codes.read_qr", ["path": .string(work.appendingPathComponent("site.png").path)]).okText
        #expect(read == "The QR code holds: https://sidefolk.app")
        await h.host.shutdown()
    }

    @Test(.enabled(if: ExtFixtures.hasAddons, ExtFixtures.noAddons))
    func pdfToolsReadCombineAndExtract() async throws {
        let h = try HostEnv()
        try await h.host.install(from: ExtFixtures.builtIn("pdf"))
        let work = try await Self.sharedFolder(h)
        Self.pdf(work.appendingPathComponent("a.pdf"), lines: ["Alpha one", "Alpha two"])
        Self.pdf(work.appendingPathComponent("b.pdf"), lines: ["Beta one"])
        let info = try #require(await h.call("ext.pdf.pdf_info", ["path": .string(work.appendingPathComponent("a.pdf").path)]).okText)
        #expect(info.hasPrefix("a.pdf: 2 pages") && info.contains("A4") && info.contains("it has text"), "\(info)")
        let text = try #require(await h.call("ext.pdf.pdf_text", ["path": .string(work.appendingPathComponent("a.pdf").path), "pages": "2"]).okText)
        #expect(text.contains("Alpha two") && !text.contains("Alpha one"), "\(text)")
        let combined = try #require(await h.call("ext.pdf.combine_pdfs", ["folder": .string(work.path), "files": ["b.pdf", "a.pdf"],
                                                                        "name": "Both"]).okText)
        #expect(combined.contains("(3 pages)"), "\(combined)")
        let extracted = try #require(await h.call("ext.pdf.extract_pages", ["folder": .string(work.path), "file": "a.pdf", "pages": "2"]).okText)
        #expect(extracted.hasPrefix("Saved 1 page of a.pdf"), "\(extracted)")
        #expect(FileManager.default.fileExists(atPath: work.appendingPathComponent("Both.pdf").path))
        #expect(FileManager.default.fileExists(atPath: work.appendingPathComponent("a (pages 2).pdf").path))
        await h.host.shutdown()
    }

    @Test(.enabled(if: ExtFixtures.hasAddons, ExtFixtures.noAddons))
    func archivesZipAndUnzipWithMacOSOwnTools() async throws {
        let h = try HostEnv()
        let info = try await h.host.install(from: ExtFixtures.builtIn("archives"))
        #expect(info.summary.texts.contains("Can run /usr/bin/zip") && info.summary.texts.contains("Can run /usr/bin/ditto"))
        let work = try await Self.sharedFolder(h)
        try FileManager.default.createDirectory(at: work.appendingPathComponent("photos"), withIntermediateDirectories: true)
        try Data("one".utf8).write(to: work.appendingPathComponent("photos/1.txt"))
        try Data("two".utf8).write(to: work.appendingPathComponent("notes.txt"))
        let zipped = try #require(await h.call("ext.archives.zip", ["folder": .string(work.path), "items": ["photos", "notes.txt"],
                                                                  "name": "Trip"]).okText)
        #expect(zipped.contains("Trip.zip") && zipped.contains("2 items"), "\(zipped)")
        let opened = try #require(await h.call("ext.archives.unzip", ["folder": .string(work.path), "file": "Trip.zip"]).okText)
        #expect(opened.contains("2 items at the top"), "\(opened)")
        #expect(try String(contentsOf: work.appendingPathComponent("Trip/photos/1.txt"), encoding: .utf8) == "one")
        let escape = await h.call("ext.archives.zip", ["folder": .string(work.path), "items": ["../elsewhere"]])
        #expect(!escape.isOK)
        await h.host.shutdown()
    }

    @Test(.enabled(if: ExtFixtures.hasAddons, ExtFixtures.noAddons),
          .enabled(if: ExtFixtures.liveNetwork, "set SIDEFOLK_LIVE_NETWORK=1 to ask the ECB and swift.org"))
    func currencyAndFeedsReachTheInternetFromTheirSandbox() async throws {
        let h = try HostEnv()
        try await h.host.install(from: ExtFixtures.builtIn("currency"))
        try await h.host.install(from: ExtFixtures.builtIn("feeds"))
        let money = try #require(await h.call("ext.currency.convert_currency", ["amount": 100, "from": "USD", "to": ["yen"]]).okText)
        #expect(money.hasPrefix("100.00 USD = ") && money.contains("JPY") && money.contains("ECB reference rates of"), "\(money)")
        let posts = try #require(await h.call("ext.feeds.read_feed", ["url": "https://www.swift.org", "count": 2]).okText)
        #expect(posts.hasPrefix("Swift.org, latest 2:"), "\(posts)")
        await h.host.shutdown()
    }
}

/// Sidefolk quarantines every file it writes (LSFileQuarantineEnabled), and Gatekeeper then held a built-in's
/// program at launch. A copy now carries exactly its original's quarantine: none for the app's own files, the
/// browser's for a downloaded folder.
struct ExtensionCopyQuarantineTests {
    @Test func aCopyIsAsTrustedAsItsOriginal() throws {
        let root = try ExtFixtures.tempDir("quarantine")
        defer { ExtensionFiles.removeTree(root.path) }
        let source = root.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("plain".utf8).write(to: source.appendingPathComponent("signed"))
        try Data("downloaded".utf8).write(to: source.appendingPathComponent("downloaded"))
        let mark = Array("0083;6ae0c3eb;Safari;".utf8)
        #expect(setxattr(source.appendingPathComponent("downloaded").path, ExtensionFiles.quarantine, mark, mark.count, 0, 0) == 0)

        try ExtensionFiles.copy(from: source.path, to: root.appendingPathComponent("copy").path)
        func quarantine(_ name: String) -> [UInt8]? {
            let path = root.appendingPathComponent("copy/\(name)").path
            let size = getxattr(path, ExtensionFiles.quarantine, nil, 0, 0, 0)
            guard size > 0 else { return nil }
            var value = [UInt8](repeating: 0, count: size)
            return getxattr(path, ExtensionFiles.quarantine, &value, size, 0, 0) == size ? value : nil
        }
        #expect(quarantine("signed") == nil)
        #expect(quarantine("downloaded") == mark)

        // The app's own built-ins: a downloaded app marks every file inside it, and the copy drops the mark.
        try ExtensionFiles.copy(from: source.path, to: root.appendingPathComponent("builtin").path, quarantine: .none)
        let size = getxattr(root.appendingPathComponent("builtin/downloaded").path, ExtensionFiles.quarantine, nil, 0, 0, 0)
        #expect(size < 0)
    }
}
