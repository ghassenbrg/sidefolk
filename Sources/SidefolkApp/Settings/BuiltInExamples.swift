import Foundation

/// One request to try for each extension that ships with Sidefolk (D39), shown under it in Settings ›
/// Extensions: a list of tool titles doesn't tell anyone what to say. Built-ins are first-party, so
/// their examples live with the app. Only the AI reads these words, and it reads every language, so
/// they are translated (GLOSSARY rule 1).
enum BuiltInExamples {
    static func request(for extensionId: String) -> String? {
        switch extensionId {
        case "dev.sidefolk.git":
            String(localized: "clone https://github.com/octocat/Hello-World into ~/Downloads",
                   comment: "A request to try with the Git extension; keep the link and the folder as they are")
        case "dev.sidefolk.world-clock":
            String(localized: "what time is it in Tokyo?", comment: "A request to try with the World Clock extension")
        case "dev.sidefolk.system-vitals":
            String(localized: "how much disk space do I have left?", comment: "A request to try with the System Vitals extension")
        case "dev.sidefolk.weather":
            String(localized: "will it rain in Lisbon this week?", comment: "A request to try with the Weather extension")
        case "dev.sidefolk.calculator":
            String(localized: "how many days until 25 December?", comment: "A request to try with the Calculator extension")
        case "dev.sidefolk.currency":
            String(localized: "how much is 50 dollars in euros?", comment: "A request to try with the Currency extension")
        case "dev.sidefolk.playtime":
            String(localized: "let's play trivia", comment: "A request to try with the Playtime extension (a quiz game)")
        case "dev.sidefolk.images":
            String(localized: "make the photos in ~/Downloads smaller", comment: "A request to try with the Images extension; keep the folder as it is")
        case "dev.sidefolk.pdf":
            String(localized: "combine the PDFs in ~/Downloads into one", comment: "A request to try with the PDF Tools extension; keep the folder as it is")
        case "dev.sidefolk.qr-codes":
            String(localized: "make a QR code of https://example.com on my Desktop", comment: "A request to try with the QR Codes extension; keep the link")
        case "dev.sidefolk.archives":
            String(localized: "zip the Screenshots folder on my Desktop", comment: "A request to try with the Archives extension")
        case "dev.sidefolk.dev-toolbox":
            String(localized: "what date is the Unix time 1800000000?", comment: "A request to try with the Dev Toolbox extension; keep the number")
        case "dev.sidefolk.feeds":
            String(localized: "what's new on the swift.org blog?", comment: "A request to try with the Feeds extension; keep the address")
        case "dev.sidefolk.system-vitals-plus":
            String(localized: "what's slowing my Mac?", comment: "A request to try with the System Vitals+ extension")
        case "dev.sidefolk.clipboard":
            String(localized: "what did I copy?", comment: "A request to try with the Clipboard extension")
        case "dev.sidefolk.keep-awake":
            String(localized: "keep my Mac awake for 2 hours", comment: "A request to try with the Keep Awake extension")
        default:
            nil
        }
    }
}
