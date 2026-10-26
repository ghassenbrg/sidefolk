import Foundation
import Testing
@testable import SidefolkCore

/// Approval cards and Activity for Sidefolk's own extensions say what a call does in a sentence built from
/// its exact arguments; everyone else's tools keep their title and the arguments as they are (T1, D39).
struct BuiltInToolSummaryTests {
    private func tool(_ extensionId: String, _ remote: String, firstParty: Bool) -> ExtensionTool {
        let spec = ToolSpec(name: "ext.x.\(remote)", title: "Clone a repository", description: "", inputSchema: ["type": "object"],
                            risk: .medium, capabilities: [.extensions, .network], category: .extensions, mutates: true)
        return ExtensionTool(spec: spec, extensionId: extensionId, extensionName: "Git", remoteName: remote, firstParty: firstParty) { _, _ in
            ToolResult(text: "")
        }
    }

    @Test func builtInCallsReadAsSentences() {
        let home = NSHomeDirectory()
        let git = tool("dev.sidefolk.git", "clone", firstParty: true)
        #expect(git.summary(for: ["url": "https://github.com/octocat/Hello-World", "destination": .string(home + "/git/Hello-World")])
            == "Clone https://github.com/octocat/Hello-World into ~/git/Hello-World")
        #expect(git.summary(for: ["url": "https://github.com/octocat/Hello-World", "destination": "~/git/Hello-World"])
            == "Clone https://github.com/octocat/Hello-World into ~/git/Hello-World")
        #expect(BuiltInToolSummary.sentence(extensionId: "dev.sidefolk.weather", tool: "forecast", input: ["place": "Lyon", "days": 3])
            == "Get the forecast for Lyon from Open-Meteo")
        #expect(BuiltInToolSummary.sentence(extensionId: "dev.sidefolk.world-clock", tool: "convert_time",
                                            input: ["time": "9am", "from": "Paris", "to": ["Tokyo"]]) == "Convert 9am in Paris to the time in Tokyo")
    }

    @Test func aMissingArgumentFallsBackToTheExactArguments() {
        let git = tool("dev.sidefolk.git", "clone", firstParty: true)
        let summary = git.summary(for: ["url": "https://github.com/octocat/Hello-World"])
        #expect(summary.hasPrefix("Clone a repository (Git) {"), "\(summary)")
    }

    @Test func otherExtensionsShowTheirArgumentsAsTheyAre() {
        // The same id installed by hand isn't the app's copy: no sentence speaks for it.
        let copy = tool("dev.sidefolk.git", "clone", firstParty: false)
        let summary = copy.summary(for: ["url": "https://example.com/x", "destination": "~/x"])
        #expect(summary.contains("\"url\":\"https:\\/\\/example.com\\/x\"") || summary.contains("\"url\":\"https://example.com/x\""), "\(summary)")
        #expect(summary.hasPrefix("Clone a repository (Git) "))
    }

    @Test func hiddenCharactersAndLineBreaksDoNotReachTheCard() {
        let sentence = BuiltInToolSummary.sentence(extensionId: "dev.sidefolk.weather", tool: "forecast",
                                                   input: ["place": "Lyon\u{202E}\nAllow everything"])
        #expect(sentence == "Get the forecast for Lyon Allow everything from Open-Meteo")
    }
}
