import Foundation
import Testing
@testable import SidefolkCore

/// The one breath the companion says aloud (D34): never a URL, a path or code.
@Suite struct SpokenLineTests {
    @Test func anAnswerIsItsFirstSentenceWithoutMarkdown() {
        let line = SpokenLine.answer("Next up is **Stretch** at 17:00. Scout is also watching example.com for changes.")
        #expect(line == "Next up is Stretch at 17:00.")
    }

    @Test func linksBecomeTheirSiteAndPathsTheirName() {
        #expect(SpokenLine.answer("I saved https://www.example.com/pricing?x=1 for you.") == "I saved example.com for you.")
        #expect(SpokenLine.answer("Watching example.com/status every 5 min.") == "Watching example.com every 5 min.")
        #expect(SpokenLine.answer("Moved it to ~/Downloads/Invoices/march.pdf yesterday.") == "Moved it to march yesterday.")
        #expect(SpokenLine.answer("See [the release notes](https://example.com/notes) first.") == "See the release notes first.")
    }

    @Test func codeIsNeverReadAloud() {
        #expect(SpokenLine.answer("Run `git status` to check.") == "Run to check.")
        #expect(SpokenLine.answer("```swift\nprint(1)\n```\nThat prints one.") == "That prints one.")
        // Nothing left to say: the words are on the screen.
        #expect(SpokenLine.answer("```\nls -la\n```") == SpokenLine.onScreen)
        #expect(SpokenLine.answer("https://example.com/a/b") == SpokenLine.onScreen)
    }

    @Test func aListIsItsCountAndFirstItem() {
        let line = SpokenLine.answer("Here's what's coming up:\n- Call the bank at 9\n- Stretch at 17:00\n- Send the deck", appLanguage: "en")
        #expect(line.hasPrefix("3"))
        #expect(line.hasSuffix("Call the bank at 9"))
        #expect(!line.contains("Stretch"))
    }

    @Test func aListInAnotherLanguageUsesItsOwnLeadIn() {
        // "3 things. First:" would be English in a French answer.
        let line = SpokenLine.answer("Voici tes rappels pour demain :\n- Appeler la banque\n- Acheter du lait", appLanguage: "en")
        #expect(line == "Voici tes rappels pour demain")
    }

    @Test func longSentencesAreCutAtAPause() {
        let long = "I looked through every note you saved this week about the trip, and the one you want is the packing list with the passport reminder at the top of it."
        let line = SpokenLine.answer(long)
        #expect(line == "I looked through every note you saved this week about the trip.")
        let unbroken = Array(repeating: "word", count: 40).joined(separator: " ")
        #expect(SpokenLine.answer(unbroken).split(separator: " ").count == SpokenLine.maxWords)
    }

    @Test func languagesWithoutSpacesAreCutByCharacters() {
        let japanese = String(repeating: "あ", count: 50) + "、" + String(repeating: "い", count: 30)
        let line = SpokenLine.clipped(japanese)
        #expect(line.count <= SpokenLine.maxCharacters + 1)
        #expect(SpokenLine.answer("明日の九時に銀行に電話します。") == "明日の九時に銀行に電話します。")
    }

    @Test func cardsSayWhatHappenedAndWhenForReminders() {
        #expect(SpokenLine.card(ResultCard(kind: .reminder, title: "Stretch", subtitle: "Today 17:00")) == "Stretch, Today 17:00")
        #expect(SpokenLine.card(ResultCard(kind: .note, title: "Saved to Inbox", subtitle: "the whole note text")) == "Saved to Inbox")
        #expect(SpokenLine.card(ResultCard(kind: .watcher, title: "Watching https://example.com/pricing every 30 min")) == "Watching example.com every 30 min")
    }

    @Test func listsOfCardsSayHowManyAndTheFirst() {
        let cards = [ResultCard(kind: .note, title: "Tea ideas"), ResultCard(kind: .note, title: "Trip notes")]
        let line = SpokenLine.list(title: "Notes", cards: cards)
        #expect(line.hasPrefix("2") && line.hasSuffix("Tea ideas"))
        #expect(SpokenLine.list(title: "Nothing found.", cards: []) == "Nothing found.")
    }
}

@Suite struct SentenceTests {
    @Test func splitsSentencesInAnyLanguage() {
        #expect(Sentences.split("Saved. I'll remind you at 9! Anything else?") == ["Saved.", "I'll remind you at 9!", "Anything else?"])
        #expect(Sentences.split("It costs 3.5 dollars, e.g. on Mondays.").count == 1)
        #expect(Sentences.split("保存しました。明日九時です。").count == 2)
        #expect(Sentences.split("  ").isEmpty)
    }
}
