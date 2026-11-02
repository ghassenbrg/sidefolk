import Foundation
import Testing

/// SwiftUI's plain button takes a click only on what is drawn, the lines of a symbol, so the app uses `.sfBare` and
/// `.sfIcon` instead (DESIGN.md › Buttons). Nothing can test SwiftUI's hit areas from the core tests; this keeps the cause out.
@Suite struct ButtonHitAreaTests {
    @Test func theAppHasNoPlainButtons() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let app = root.appendingPathComponent("Sources/SidefolkApp")
        let files = try #require(FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil))
        var found: [String] = []
        var read = 0
        for case let file as URL in files where file.pathExtension == "swift" {
            read += 1
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: .newlines)
            for (i, line) in lines.enumerated() where line.contains(".buttonStyle(.plain)") || line.contains("PlainButtonStyle") {
                found.append("\(file.lastPathComponent):\(i + 1)")
            }
        }
        #expect(read > 100, "read too few files to mean anything")
        #expect(found.isEmpty, "use .sfBare or .sfIcon: \(found)")
    }
}
