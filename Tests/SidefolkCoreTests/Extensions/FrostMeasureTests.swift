import Testing
@testable import SidefolkCore

/// The rule behind a frosted card (D150): measured, so it holds for any picture.
struct FrostMeasureTests {
    @Test func aPictureWithoutColourDoesntCount() {
        #expect(!FrostMeasure.hasColour(Array(repeating: (0.98, 0.98, 0.98), count: 10)), "a white page")
        #expect(!FrostMeasure.hasColour(Array(repeating: (0.4, 0.42, 0.41), count: 10)), "a grey blur")
        #expect(FrostMeasure.hasColour(Array(repeating: (0.8, 0.4, 0.2), count: 10)), "a sunset")
    }

    @Test(arguments: [(1.0, 1.0, 1.0), (1.0, 0.9, 0.2), (0.2, 1.0, 0.9), (0.5, 0.5, 0.5), (0.05, 0.05, 0.1)])
    func whiteTextStaysReadableOnAnyPicture(colour: (Double, Double, Double)) {
        let pixels: [FrostMeasure.Pixel] = [(0, 0, 0), (r: colour.0, g: colour.1, b: colour.2)]
        let scrim = FrostMeasure.scrim(pixels)
        #expect(FrostMeasure.worst(pixels, scrim: scrim) >= FrostMeasure.contrast)
    }

    @Test func theBrightestPartDecides() {
        let dark: [FrostMeasure.Pixel] = [(0.1, 0.1, 0.1)]
        #expect(FrostMeasure.scrim(dark + [(1, 1, 1)]) > FrostMeasure.scrim(dark))
    }
}
