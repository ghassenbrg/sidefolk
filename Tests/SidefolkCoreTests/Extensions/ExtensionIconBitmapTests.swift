import CoreGraphics
import Foundation
import Testing
@testable import SidefolkCore

/// A PDF icon is drawn once, in a process that can be killed, and only ever shown as that bitmap.
@Suite(.serialized) struct ExtensionIconBitmapTests {
    private func file(_ data: Data) throws -> String {
        let path = NSTemporaryDirectory() + UUID().uuidString + ".pdf"
        try data.write(to: URL(fileURLWithPath: path))
        return path
    }

    /// Forms inside forms, each drawing the next many times: a few kilobytes that take minutes. Hand-written, as no PDF writer makes this.
    /// `salt` makes the bytes new each run, or the remembered answer would be all this tests.
    private func costly(levels: Int = 5, salt: String = UUID().uuidString) -> Data {
        var objects = ["<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
                       "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 512 512] /Contents 4 0 R /Resources << /XObject << /F 5 0 R >> >> >>"]
        let draw = String(repeating: "/F Do\n", count: 40), paint = String(repeating: "0.5 g 0 0 512 512 re f\n", count: 20)
        objects.append("<< /Length \(draw.utf8.count) >>\nstream\n\(draw)\nendstream")
        for level in 0..<levels {
            let inner = level + 1 < levels ? "/Resources << /XObject << /F \(6 + level) 0 R >> >>" : ""
            let body = level + 1 < levels ? draw : paint
            objects.append("<< /Type /XObject /Subtype /Form /BBox [0 0 512 512] \(inner) /Length \(body.utf8.count) >>\nstream\n\(body)\nendstream")
        }
        var text = "%PDF-1.4\n% \(salt)\n"
        for (index, object) in objects.enumerated() { text += "\(index + 1) 0 obj\n\(object)\nendobj\n" }
        text += "trailer << /Root 1 0 R /Size \(objects.count + 1) >>\n"
        return Data(text.utf8)
    }

    @Test func anOrdinaryIconBecomesAPicture() throws {
        let path = NSTemporaryDirectory() + UUID().uuidString + ".pdf"
        defer { try? FileManager.default.removeItem(atPath: path) }
        var box = CGRect(x: 0, y: 0, width: 512, height: 512)
        let context = try #require(CGContext(URL(fileURLWithPath: path) as CFURL, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(red: CGFloat.random(in: 0...1), green: 0.4, blue: 0.2, alpha: 1))
        context.fill(box)
        context.endPDFPage()
        context.closePDF()
        let bitmap = try #require(ExtensionIconBitmap.path(forPDF: path))
        #expect(bitmap.hasSuffix(".png"))
        #expect(FileManager.default.contents(atPath: bitmap)?.starts(with: [0x89, 0x50, 0x4E, 0x47]) == true)
    }

    @Test func aCostlyIconIsCutOffAndRemembered() throws {
        let path = try file(costly())
        defer { try? FileManager.default.removeItem(atPath: path) }
        let began = Date()
        #expect(ExtensionIconBitmap.path(forPDF: path) == nil)
        let took = Date().timeIntervalSince(began)
        #expect(took > 1 && took < 6, "really drawn, and cut off at its limit: \(took)")
        let again = Date()
        #expect(ExtensionIconBitmap.path(forPDF: path) == nil)
        #expect(Date().timeIntervalSince(again) < 0.5, "not drawn twice")
    }

    @Test func aHugePageIsRefusedBeforeAnyDrawing() throws {
        let path = NSTemporaryDirectory() + UUID().uuidString + ".pdf"
        defer { try? FileManager.default.removeItem(atPath: path) }
        var box = CGRect(x: 0, y: 0, width: 14400, height: 14400)
        let context = try #require(CGContext(URL(fileURLWithPath: path) as CFURL, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        context.endPDFPage()
        context.closePDF()
        #expect(ExtensionIcon.problem(try Data(contentsOf: URL(fileURLWithPath: path)), fileName: "icon.pdf")?.contains("too large") == true)
    }
}
