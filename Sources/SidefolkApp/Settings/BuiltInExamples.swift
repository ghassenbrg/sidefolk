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
        default:
            nil
        }
    }
}
