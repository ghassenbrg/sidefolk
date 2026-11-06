import Foundation
@testable import SidefolkCore
import Testing

/// A card shows a path as it is, with anything that draws nothing or turns the text around written out, so one name can't pass for another (T13).
@Suite struct HiddenCharactersShownTests {
    @Test func aDirectionControlInAPathIsWrittenOut() {
        let shown = FolderAccess.displayPath("/Users/me/Downloads/report\u{202E}fdp.exe")
        #expect(shown == "/Users/me/Downloads/report⟨U+202E⟩fdp.exe", shown)
        #expect(!shown.unicodeScalars.contains("\u{202E}"))
    }

    @Test func zeroWidthTagAndSeparatorCharactersAreWrittenOutToo() {
        #expect("a\u{200B}b".hiddenShown == "a⟨U+200B⟩b")
        #expect("a\u{2068}b\u{2069}".hiddenShown == "a⟨U+2068⟩b⟨U+2069⟩")
        #expect("a\u{E0061}b".hiddenShown == "a⟨U+E0061⟩b")
        #expect("a\u{2028}b".hiddenShown == "a⟨U+2028⟩b")
        #expect("a\u{FEFF}b".hiddenShown == "a⟨U+FEFF⟩b")
    }

    @Test func ordinaryTextIsUntouched() {
        for text in ["/Users/me/Documents/Taxes 2025.pdf", "~/Café/naïve.txt", "/tmp/日本語/ملف.txt", "/tmp/emoji 🙂.txt"] {
            #expect(text.hiddenShown == text, Comment(rawValue: text))
        }
    }

    @Test func aClipNeverCutsAMarkerInHalf() {
        // The cut at 239 characters would fall inside the marker.
        let text = (String(repeating: "a", count: 237) + "\u{202E}" + String(repeating: "b", count: 50)).hiddenShown
        let clipped = text.clipped(240)
        #expect(clipped.count <= 240 && clipped.hasSuffix("…"))
        #expect(!clipped.contains("⟨") || clipped.contains("⟩"), "no half marker: \(clipped.suffix(12))")
        // A marker that fits whole stays.
        let fits = (String(repeating: "a", count: 10) + "\u{202E}" + String(repeating: "b", count: 300)).hiddenShown.clipped(240)
        #expect(fits.contains("⟨U+202E⟩"))
    }

    @Test func theSummaryOfAFileToolShowsTheMarker() {
        let tool = FilesRevealTool(platform: RecordingPlatform())
        let summary = tool.summary(for: ["path": "/private/tmp/sidefolk-nonexistent/report\u{202E}fdp.exe"])
        #expect(summary.contains("⟨U+202E⟩") && !summary.unicodeScalars.contains("\u{202E}"), Comment(rawValue: summary))
    }
}
