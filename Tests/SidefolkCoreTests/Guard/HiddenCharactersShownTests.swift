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

    @Test func whatUnicodeCallsIgnorableIsWrittenOutAndFillersAndSelectorsToo() {
        for scalar in ["\u{034F}", "\u{FE00}", "\u{E0100}", "\u{17B4}", "\u{180B}", "\u{115F}", "\u{3164}", "\u{FFA0}", "\u{00AD}", "\u{061C}", "\u{0085}"] {
            let shown = "invoice\(scalar).pdf".hiddenShown
            #expect(shown.contains("⟨U+") && shown.hasSuffix(".pdf") && shown != "invoice\(scalar).pdf", Comment(rawValue: "\(scalar.unicodeScalars.first!.value)"))
        }
        // A variation selector with nothing to select, or a second one, is not part of an emoji.
        #expect("e\u{FE0F}".hiddenShown == "e⟨U+FE0F⟩")
        #expect("🙂\u{FE0F}\u{FE0F}".hiddenShown == "🙂⟨U+FE0F⟩⟨U+FE0F⟩")
    }

    @Test func onlyWhatMakesUpAnEmojiKeepsItsJoinersAndSelectors() {
        // Kept: a family, a person with a job, a heart drawn as text then as emoji, a keycap, a flag.
        for text in ["👨\u{200D}👩\u{200D}👧.png", "❤\u{FE0F}.txt", "1\u{FE0F}\u{20E3}.txt", "👩\u{200D}❤\u{FE0F}\u{200D}👨", "#\u{FE0F}\u{20E3}", "🇯🇵 trip.txt"] {
            #expect(text.hiddenShown == text, Comment(rawValue: text))
        }
        // Marked: a selector after a plain digit (`invoice-2025.pdf` with a hidden character), after letters, an emoji drawn as emoji already, FE0E always.
        #expect("invoice-2025\u{FE0F}.pdf".hiddenShown == "invoice-2025⟨U+FE0F⟩.pdf")
        #expect("a\u{FE0F}".hiddenShown == "a⟨U+FE0F⟩")
        #expect("🙂\u{FE0F}".hiddenShown == "🙂⟨U+FE0F⟩")
        #expect("🙂\u{FE0E}".hiddenShown == "🙂⟨U+FE0E⟩")
        #expect("❤\u{FE0E}".hiddenShown == "❤⟨U+FE0E⟩")
        #expect("❤\u{FE0F}\u{FE0F}".hiddenShown == "❤\u{FE0F}⟨U+FE0F⟩")
        // Marked: every other joiner, in Latin, Arabic, Persian and Indic writing, at an edge or between digits.
        #expect("inv\u{200C}oice".hiddenShown == "inv⟨U+200C⟩oice")
        #expect("a\u{200D}b".hiddenShown == "a⟨U+200D⟩b")
        #expect("🙂\u{200D}".hiddenShown == "🙂⟨U+200D⟩")
        #expect("1\u{200D}2".hiddenShown == "1⟨U+200D⟩2")
        #expect("می\u{200C}خواهم".hiddenShown == "می⟨U+200C⟩خواهم", "Persian too: noise, but honest")
        #expect("ب\u{200D}ا".hiddenShown == "ب⟨U+200D⟩ا")
        #expect("ا\u{200D}ب".hiddenShown == "ا⟨U+200D⟩ب", "a letter that doesn't join")
        #expect("क\u{094D}\u{200C}ष".hiddenShown == "क\u{094D}⟨U+200C⟩ष")
        #expect("क\u{094D}\u{200D}ष".hiddenShown == "क\u{094D}⟨U+200D⟩ष")
        #expect("\u{E0067}x".hiddenShown == "⟨U+E0067⟩x", "tag characters carry hidden text: never kept")
        #expect("🏴\u{E0067}\u{E007F}".hiddenShown == "🏴⟨U+E0067⟩⟨U+E007F⟩", "the England flag shows markers: accepted")
        #expect("a\u{180B}b".hiddenShown == "a⟨U+180B⟩b", "a Mongolian selector shows a marker: accepted")
    }

    @Test func renameAndTrashCardsShowTheNamesWithTheirHiddenCharacters() {
        let rename = FilesRenameTool().summary(for: ["path": "/Users/me/Downloads/photo.jpg", "new_name": "photo\u{202E}gpj.txt"])
        #expect(rename.contains("photo⟨U+202E⟩gpj.txt") && !rename.unicodeScalars.contains("\u{202E}"), Comment(rawValue: rename))
        let trash = FilesTrashTool().summary(for: ["paths": ["/Users/me/Shared/report\u{202E}fdp.exe", "/Users/me/Shared/a.txt"]])
        #expect(trash.contains("report⟨U+202E⟩fdp.exe") && !trash.unicodeScalars.contains("\u{202E}"), Comment(rawValue: trash))
        let oldName = FilesRenameTool().summary(for: ["path": "/Users/me/Downloads/old\u{034F}.pdf", "new_name": "new.pdf"])
        #expect(oldName.contains("old⟨U+034F⟩.pdf"), Comment(rawValue: oldName))
    }

    @Test func theSummaryOfAFileToolShowsTheMarker() {
        let tool = FilesRevealTool(platform: RecordingPlatform())
        let summary = tool.summary(for: ["path": "/private/tmp/sidefolk-nonexistent/report\u{202E}fdp.exe"])
        #expect(summary.contains("⟨U+202E⟩") && !summary.unicodeScalars.contains("\u{202E}"), Comment(rawValue: summary))
    }
}
