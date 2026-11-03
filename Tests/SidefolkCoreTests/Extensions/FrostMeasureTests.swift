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

    /// A black-and-white photo is a picture; a page of text and a blank page aren't.
    @Test func aPictureNeedsColourOrTones() {
        let photo: [FrostMeasure.Pixel] = (0..<100).map { let v = Double($0) / 99; return (v, v, v) }
        let page: [FrostMeasure.Pixel] = (0..<100).map { $0 < 92 ? (1, 1, 1) : (0.1, 0.1, 0.1) }
        #expect(FrostMeasure.isPicture(photo))
        #expect(!FrostMeasure.isPicture(page))
        #expect(!FrostMeasure.isPicture(Array(repeating: (1, 1, 1), count: 100)))
        #expect(FrostMeasure.isPicture(Array(repeating: (0.8, 0.4, 0.2), count: 100)))
    }

    @Test func theBrightestPartDecides() {
        let dark: [FrostMeasure.Pixel] = [(0.1, 0.1, 0.1)]
        #expect(FrostMeasure.scrim(dark + [(1, 1, 1)]) > FrostMeasure.scrim(dark))
    }
}
