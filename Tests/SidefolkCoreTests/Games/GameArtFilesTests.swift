import Foundation
import ImageIO
import Testing
@testable import SidefolkCore

/// The games' pictures in the app (D79 amended, the look v2): every look has its scene by day and at night (the arcade
/// is night already; the best of three borrows the living room), the night painted on the day's frame so its table
/// is cut from the same place, an icon each, and the folder within its budget.
struct GameArtFilesTests {
    static let art = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/SidefolkApp/Play/Art")

    /// The scene a look stands in, as `GameStyle.of` names it.
    static func scene(_ look: GameLook) -> String { look == .hands ? "cups" : look.rawValue }

    static func size(_ url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return CGSize(width: w, height: h)
    }

    @Test(arguments: GameLook.allCases)
    func everyLookHasItsSceneByDayAndAtNight(_ look: GameLook) throws {
        let day = Self.art.appendingPathComponent("game-bg-\(Self.scene(look)).heic")
        let daySize = try #require(Self.size(day), "\(day.lastPathComponent)")
        #expect(FileManager.default.fileExists(atPath: Self.art.appendingPathComponent("game-icon-\(look.rawValue).webp").path))
        guard look != .arcade else { return }
        let night = Self.art.appendingPathComponent("game-bg-\(Self.scene(look))-night.heic")
        let nightSize = try #require(Self.size(night), "\(night.lastPathComponent)")
        #expect(nightSize == daySize, "the night is the day's frame, so the table strip is cut from the same rows")
    }

    @Test func theArtStaysWithinItsBudget() throws {
        let files = try FileManager.default.contentsOfDirectory(at: Self.art, includingPropertiesForKeys: [.fileSizeKey])
        let total = try files.reduce(0) { $0 + (try $1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
        #expect(total < 3_000_000, "about 1.5 MB today; a few MB at most")
        for file in files where file.lastPathComponent.hasPrefix("game-bg-") {
            let bytes = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            #expect(bytes < 100_000, "\(file.lastPathComponent): a softened scene, not a photograph")
        }
    }
}
