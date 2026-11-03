import Foundation

/// The rule behind a card frosted from a person's file, measured and not judged by eye (D150): a picture counts only if it still
/// has colour once blurred, and the scrim over it is the least that keeps white text readable on its brightest part.
public enum FrostMeasure {
    public typealias Pixel = (r: Double, g: Double, b: Double)

    /// What's left of a picture's colour once the scrim is over it. Below this it's grey mud on the card, whatever it was before: white
    /// pages, screenshots and pale tints, but also stripes and a dark photo with one bright spot, whose scrim is heavy.
    public static let minimumShownChroma = 0.10
    /// Below this, a thumbnail is a page of text or a blank document, not a picture worth showing on the file's sheet.
    public static let minimumPictureChroma = 0.06

    /// Colour, or tones across the range as a black-and-white photo has: a page is nearly all paper.
    public static func isPicture(_ pixels: [Pixel]) -> Bool {
        if chroma(pixels) >= minimumPictureChroma { return true }
        let mid = pixels.filter { let v = ($0.r + $0.g + $0.b) / 3; return v > 0.15 && v < 0.85 }
        return Double(mid.count) >= Double(pixels.count) * 0.4
    }
    /// For white. It keeps the softer detail text, white at 92%, above 4.5:1 on the brightest part.
    public static let contrast = 5.6

    public static func chroma(_ pixels: [Pixel]) -> Double {
        pixels.map { max($0.r, $0.g, $0.b) - min($0.r, $0.g, $0.b) }.reduce(0, +) / Double(max(pixels.count, 1))
    }

    public static func hasColour(_ pixels: [Pixel]) -> Bool { chroma(pixels) * (1 - scrim(pixels)) >= minimumShownChroma }

    /// White against the brightest pixel, under this much black.
    public static func worst(_ pixels: [Pixel], scrim: Double) -> Double {
        func line(_ v: Double) -> Double {
            let s = v * (1 - scrim)
            return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        let brightest = pixels.map { 0.2126 * line($0.r) + 0.7152 * line($0.g) + 0.0722 * line($0.b) }.max() ?? 0
        return 1.05 / (brightest + 0.05)
    }

    public static func scrim(_ pixels: [Pixel]) -> Double {
        var amount = 0.2
        while amount < 0.92, worst(pixels, scrim: amount) < contrast { amount += 0.01 }
        return amount
    }
}
