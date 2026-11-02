import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import SidefolkCore

/// Pack assets (D99, T40): the caps, hostile files, and that a load reads only what was installed.
struct PackAssetsTests {
    static func png(_ width: Int = 16, _ height: Int = 16) -> Data { encode(width, height, type: UTType.png) }

    static func encode(_ width: Int, _ height: Int, type: UTType, frames: Int = 1) -> Data {
        let c = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        c.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = c.makeImage()!
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, type.identifier as CFString, frames, nil)!
        for _ in 0..<frames { CGImageDestinationAddImage(dest, image, nil) }
        #expect(CGImageDestinationFinalize(dest))
        return out as Data
    }

    /// A short WAV of silence.
    static func wav(seconds: Double, rate: Int = 22050) -> Data {
        let samples = Int(Double(rate) * seconds)
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8))
        u32(UInt32(36 + samples * 2))
        d.append(contentsOf: Array("WAVEfmt ".utf8))
        u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate * 2)); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8))
        u32(UInt32(samples * 2))
        d.append(Data(count: samples * 2))
        return d
    }

    @Test func aPathStaysInThePack() {
        for good in ["cup.png", "cups/red cup.png", "fond/été-1.webp", "a/b/c.jpg"] { #expect(PackAssets.clean(good) == good, "\(good)") }
        for bad in ["", "/a.png", "../a.png", "a/../b.png", "a//b.png", ".a.png", "a/.b/c.png", "a\\b.png", "file:a.png", "http://x/a.png", "a?.png", String(repeating: "a/", count: 9) + "b.png", String(repeating: "x", count: 300) + ".png"] {
            #expect(PackAssets.clean(bad) == nil, "\(bad)")
        }
    }

    @Test func goodPicturesPass() {
        #expect(PackAssets.imageProblem(Self.png(), fileName: "a.png") == nil)
        #expect(PackAssets.imageProblem(Self.encode(32, 32, type: .jpeg), fileName: "a.jpg") == nil)
        #expect(PackAssets.imageProblem(Self.encode(32, 32, type: .heic), fileName: "a.heic") == nil)
        #expect(PackAssets.decodeImage(Self.png(), fileName: "a.png", maxSide: 8)?.width == 8, "decoded no larger than asked")
    }

    @Test func hostilePicturesAreRefusedBeforeAnyPixelIsDecoded() {
        // A type that says one thing and is another.
        #expect(PackAssets.imageProblem(Self.png(), fileName: "a.jpg")?.contains("says .jpg") == true)
        // Text, SVG with a link out, and types off the list.
        #expect(PackAssets.imageProblem(Data("not a picture".utf8), fileName: "a.png") != nil)
        let svg = Data(#"<svg xmlns="http://www.w3.org/2000/svg"><image href="file:///etc/passwd"/></svg>"#.utf8)
        #expect(PackAssets.imageProblem(svg, fileName: "a.svg") != nil)
        #expect(PackAssets.imageProblem(svg, fileName: "a.png") != nil)
        #expect(PackAssets.imageProblem(Self.encode(8, 8, type: .gif), fileName: "a.gif") != nil)
        #expect(PackAssets.imageProblem(Self.encode(8, 8, type: .tiff), fileName: "a.png") != nil)
        // Empty and truncated files draw nothing, and never stop anything.
        #expect(PackAssets.imageProblem(Data(), fileName: "a.png") != nil)
        let cut = Self.png(64, 64).prefix(40)
        #expect(PackAssets.decodeImage(cut, fileName: "a.png", maxSide: 64) == nil)
        #expect(PackAssets.decodeImage(Data(repeating: 0x89, count: 4096), fileName: "a.png", maxSide: 64) == nil)
        // An animation is a timer by the back door.
        let frames = Self.encode(8, 8, type: .png, frames: 3)
        #expect(PackAssets.imageProblem(frames, fileName: "a.png") != nil || PackAssets.decodeImage(frames, fileName: "a.png", maxSide: 8) != nil)
        // Too many bytes.
        #expect(PackAssets.imageProblem(Data(count: PackAssets.maxImageBytes + 1), fileName: "a.png")?.contains("MiB") == true)
    }

    @Test func aPixelBombIsReadFromItsHeaderAndRefused() {
        // A small file whose header claims 60000 × 60000: refused without allocating it.
        var bomb = Self.png(8, 8)
        func put(_ v: UInt32, at: Int) { withUnsafeBytes(of: v.bigEndian) { bomb.replaceSubrange(at..<at + 4, with: $0) } }
        put(60000, at: 16)
        put(60000, at: 20)
        #expect(bomb.count < 1024)
        let started = Date()
        #expect(PackAssets.imageProblem(bomb, fileName: "a.png") != nil)
        #expect(PackAssets.decodeImage(bomb, fileName: "a.png", maxSide: 4096) == nil)
        #expect(Date().timeIntervalSince(started) < 1)
        // And a real picture past the caps.
        #expect(PackAssets.imageProblem(Self.png(PackAssets.maxImageSide + 1, 2), fileName: "a.png")?.contains("pixels") == true)
        #expect(PackAssets.imageProblem(Self.png(2500, 2500), fileName: "a.png")?.contains("million") == true)
    }

    @Test func soundsHaveTheirCaps() throws {
        let dir = try ExtFixtures.tempDir("sounds")
        func file(_ name: String, _ data: Data) throws -> URL {
            let url = dir.appendingPathComponent(name)
            try data.write(to: url)
            return url
        }
        #expect(PackAssets.soundProblem(try file("ok.wav", Self.wav(seconds: 0.2))) == nil)
        #expect(PackAssets.soundProblem(try file("long.wav", Self.wav(seconds: 11, rate: 8000)))?.contains("lasts") == true)
        #expect(PackAssets.soundProblem(try file("big.wav", Self.wav(seconds: 60))) != nil)
        #expect(PackAssets.soundProblem(try file("fake.wav", Data("hello".utf8))) != nil)
        #expect(PackAssets.soundProblem(try file("a.mp4", Self.wav(seconds: 0.2))) != nil)
    }

    func folder(_ files: [String: Data]) throws -> URL {
        let dir = try ExtFixtures.tempDir("assets")
        for (path, data) in files {
            let url = dir.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        return dir
    }

    @Test func theFolderCheckFindsEachProblemAndTheBudget() throws {
        let good = try folder(["a.png": Self.png(), "sub/b.wav": Self.wav(seconds: 0.1)])
        #expect(PackAssets.check(folder: good.path).problems.isEmpty)
        #expect(PackAssets.check(folder: good.path).files == ["a.png", "sub/b.wav"])

        let bad = try folder(["script.py": Data("print()".utf8), "x.png": Data("no".utf8), ".hidden.png": Self.png()])
        let problems = PackAssets.check(folder: bad.path).problems
        #expect(problems.contains { $0.path == "script.py" } && problems.contains { $0.path == "x.png" } && problems.contains { $0.path == ".hidden.png" })

        let linked = try folder(["a.png": Self.png()])
        try FileManager.default.createSymbolicLink(atPath: linked.appendingPathComponent("out.png").path, withDestinationPath: "/etc/hosts")
        #expect(PackAssets.check(folder: linked.path).problems.first?.message.contains("link") == true, "a link out of the pack")

        // A budget's worth of files: past the total, though each passes.
        let one = Self.png(1800, 1800)
        var many: [String: Data] = [:]
        let copies = PackAssets.maxTotalBytes / max(one.count, 1) + 2
        if copies <= PackAssets.maxFiles {
            for i in 0..<copies { many["p\(i).png"] = one }
            let report = PackAssets.check(folder: try folder(many).path)
            #expect(report.problems.contains { $0.message.contains("MiB") })
        }
        var lots: [String: Data] = [:]
        for i in 0...PackAssets.maxFiles { lots["p\(i).png"] = Self.png(2, 2) }
        #expect(PackAssets.check(folder: try folder(lots).path).problems.contains { $0.message.contains("at most") })
    }

    @Test func aLoadReadsOnlyWhatWasInstalled() throws {
        let png = Self.png()
        let dir = try folder(["a.png": png, "b.png": png])
        let reader = PackAssetReader(root: dir.path, prefix: "assets", pins: ["assets/a.png": ExtensionHash.sha256(png), "assets/gone.png": "x"])
        #expect(reader.data("a.png") == png)
        #expect(reader.image("a.png", maxSide: 8) != nil)
        #expect(reader.has("a.png") && !reader.has("b.png"))
        #expect(reader.data("b.png") == nil, "not pinned")
        #expect(reader.data("gone.png") == nil)
        #expect(reader.data("../a.png") == nil && reader.data("/etc/hosts") == nil)
        // Changed after install: its bytes no longer match.
        try Self.encode(9, 9, type: .png).write(to: dir.appendingPathComponent("a.png"))
        #expect(reader.data("a.png") == nil)
        // Replaced by a link.
        let linked = try folder([:])
        try FileManager.default.createSymbolicLink(atPath: linked.appendingPathComponent("a.png").path, withDestinationPath: dir.appendingPathComponent("b.png").path)
        let through = PackAssetReader(root: linked.path, prefix: "assets", pins: ["assets/a.png": ExtensionHash.sha256(png)])
        #expect(through.data("a.png") == nil)
    }
}
