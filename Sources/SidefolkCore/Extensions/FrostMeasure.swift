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

    /// The ring's slice under the pointer (D152): this picture's own hue, strong, and dark enough for white words at 4.5:1. nil when the
    /// picture has too little colour to take one from.
    public static func vivid(_ pixels: [Pixel]) -> Pixel? {
        var x = 0.0, y = 0.0
        for p in pixels {
            let high = max(p.r, p.g, p.b), low = min(p.r, p.g, p.b), c = high - low
            guard c > 0 else { continue }
            let hue: Double = high == p.r ? (p.g - p.b) / c : high == p.g ? 2 + (p.b - p.r) / c : 4 + (p.r - p.g) / c
            x += cos(hue * .pi / 3) * c
            y += sin(hue * .pi / 3) * c
        }
        guard chroma(pixels) >= minimumPictureChroma else { return nil }
        return vivid(hue: atan2(y, x) / (2 * .pi))
    }

    /// `hue` as a turn, 0 to 1.
    public static func vivid(hue: Double) -> Pixel {
        let h = (hue.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) * 6
        func pixel(_ value: Double) -> Pixel {
            let c = value * 0.8, x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1)), m = value - c
            let (r, g, b): (Double, Double, Double) = switch Int(h) {
            case 0: (c, x, 0)
            case 1: (x, c, 0)
            case 2: (0, c, x)
            case 3: (0, x, c)
            case 4: (x, 0, c)
            default: (c, 0, x)
            }
            return (r + m, g + m, b + m)
        }
        var value = 0.95
        while value > 0.3, worst([pixel(value)], scrim: 0) < 4.5 { value -= 0.01 }
        return pixel(value)
    }

    public static func scrim(_ pixels: [Pixel]) -> Double {
        var amount = 0.2
        while amount < 0.92, worst(pixels, scrim: amount) < contrast { amount += 0.01 }
        return amount
    }
}
