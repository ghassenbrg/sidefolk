import CoreGraphics
import Foundation
import Testing
@testable import SidefolkCore

/// The rule behind a frosted card (D150): measured, so it holds for any picture.
struct FrostMeasureTests {
    @Test func aPictureWithoutColourDoesntCount() {
        #expect(!FrostMeasure.hasColour(Array(repeating: (0.98, 0.98, 0.98), count: 10)), "a white page")
        #expect(!FrostMeasure.hasColour(Array(repeating: (0.4, 0.42, 0.41), count: 10)), "a grey blur")
        #expect(FrostMeasure.hasColour(Array(repeating: (0.8, 0.4, 0.2), count: 10)), "a sunset")
        // Colourful enough before the scrim, grey after it: bright stripes need so much black that nothing is left.
        #expect(!FrostMeasure.hasColour(Array(repeating: (0.98, 0.9, 0.9), count: 10)), "a pale tint")
    }

    @Test(arguments: [(1.0, 1.0, 1.0), (1.0, 0.9, 0.2), (0.2, 1.0, 0.9), (0.5, 0.5, 0.5), (0.05, 0.05, 0.1)])
    func whiteTextStaysReadableOnAnyPicture(colour: (Double, Double, Double)) {
        let pixels: [FrostMeasure.Pixel] = [(0, 0, 0), (r: colour.0, g: colour.1, b: colour.2)]
        let scrim = FrostMeasure.scrim(pixels)
        #expect(FrostMeasure.worst(pixels, scrim: scrim) >= FrostMeasure.contrast)
    }

    /// A few bytes of PDF can ask for gigabytes of bitmap, on any card with no colourful picture.
    @Test func anIconCantAskForAnEnormousPage() throws {
        func pdf(_ side: CGFloat) throws -> URL {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
            var box = CGRect(x: 0, y: 0, width: side, height: side)
            let context = try #require(CGContext(url as CFURL, mediaBox: &box, nil))
            context.beginPDFPage(nil)
            context.endPDFPage()
            context.closePDF()
            return url
        }
        let large = try pdf(14400), fine = try pdf(512)
        defer { for url in [large, fine] { try? FileManager.default.removeItem(at: url) } }
        #expect(ExtensionIcon.problem(try Data(contentsOf: large), fileName: "icon.pdf")?.contains("too large") == true)
        #expect(ExtensionIcon.problem(try Data(contentsOf: fine), fileName: "icon.pdf") == nil)
    }

    /// A few kilobytes of forms inside forms take minutes to draw. Hand-written, as no PDF writer makes this.
    @Test func anIconCantNestItsDrawing() {
        func pdf(forms: Int, uses: Int = 2) -> Data {
            var objects = ["<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>"]
            let first = 5
            objects.append("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 512 512] /Contents 4 0 R /Resources << /XObject << /F \\(first) 0 R >> >> >>".replacingOccurrences(of: "\\(first)", with: "\(first)"))
            let draw = String(repeating: "/F Do ", count: uses)
            objects.append("<< /Length \(draw.utf8.count) >>\nstream\n\(draw)\nendstream")
            for level in 0..<forms {
                let inner = level + 1 < forms ? "/Resources << /XObject << /F \(first + level + 1) 0 R >> >>" : ""
                objects.append("<< /Type /XObject /Subtype /Form /BBox [0 0 512 512] \(inner) /Length \(draw.utf8.count) >>\nstream\n\(draw)\nendstream")
            }
            var text = "%PDF-1.4\n"
            for (index, object) in objects.enumerated() { text += "\(index + 1) 0 obj\n\(object)\nendobj\n" }
            text += "trailer << /Root 1 0 R /Size \(objects.count + 1) >>\n"
            return Data(text.utf8)
        }
        #expect(ExtensionIcon.problem(pdf(forms: 1), fileName: "icon.pdf") == nil, "one form is ordinary")
        #expect(ExtensionIcon.problem(pdf(forms: 12), fileName: "icon.pdf")?.contains("nests") == true)
        #expect(ExtensionIcon.problem(pdf(forms: 1, uses: 1000), fileName: "icon.pdf")?.contains("too many times") == true)
    }

    @Test func theBrightestPartDecides() {
        let dark: [FrostMeasure.Pixel] = [(0.1, 0.1, 0.1)]
        #expect(FrostMeasure.scrim(dark + [(1, 1, 1)]) > FrostMeasure.scrim(dark))
    }
}
