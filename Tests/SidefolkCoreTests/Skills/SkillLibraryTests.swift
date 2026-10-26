import Foundation
import Testing
@testable import SidefolkCore

@Suite final class SkillLibraryTests {
    let root: URL
    let library: SkillLibrary
    let trashDir: URL
    static let bundled = ExtFixtures.repoRoot.appendingPathComponent("Resources/Skills", isDirectory: true)

    init() throws {
        root = try ExtFixtures.tempDir("skills")
        let trash = root.appendingPathComponent("Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        trashDir = trash
        // Never the user's real Trash.
        library = SkillLibrary(userDirectory: root.appendingPathComponent("Skills", isDirectory: true),
                               bundledDirectory: Self.bundled) { url in
            let dest = trash.appendingPathComponent(UUID().uuidString)
            try FileManager.default.moveItem(at: url, to: dest)
            return dest
        }
    }

    deinit { ExtensionFiles.removeTree(root.path) }

    func write(_ name: String, _ text: String) throws {
        let dir = root.appendingPathComponent("Skills/\(name)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: dir.appendingPathComponent("SKILL.md"))
    }

    @Test func parsesFrontmatterForms() throws {
        let (front, body) = try SkillDocument.parse("""
        ---
        name: trip
        description: "Plan a \\"trip\\": flights, hotel"
        tools: [web.fetch, 'notes.save']
        other:
          - a
          - "b"
        model: smart
        license: MIT
        ---
        # Steps
        1. Go.
        """)
        #expect(front["name"] == ["trip"])
        #expect(front["description"] == [#"Plan a "trip": flights, hotel"#])
        #expect(front["tools"] == ["web.fetch", "notes.save"])
        #expect(front["other"] == ["a", "b"])
        #expect(front["model"] == ["smart"])
        #expect(body == "# Steps\n1. Go.")
        #expect(throws: UserFacingError.self) { try SkillDocument.parse("no frontmatter") }
        #expect(throws: UserFacingError.self) { try SkillDocument.parse("---\nname: x\n") }
    }

    @Test func bundledSkillsAreUsable() throws {
        let skills = SkillLibrary(userDirectory: root.appendingPathComponent("none"), bundledDirectory: Self.bundled).skills()
        #expect(skills.map(\.name) == ["organize-downloads", "weekly-review"])
        for s in skills {
            #expect(s.origin == .bundled && s.trusted)
            #expect(!s.description.isEmpty && s.instructions.count > 300)
            #expect(!s.tools.isEmpty)
        }
        #expect(skills.last?.model == "smart")
        #expect(skills.first?.tools == ["files.list", "files.mkdir", "files.move"])
    }

    @Test func indexMergesUserAndBundledSkills() throws {
        try write("tidy-desk", "---\nname: tidy-desk\ndescription: Clean the Desktop.\n---\nSteps")
        try write("weekly-review", "---\nname: weekly-review\ndescription: My own review.\n---\nMine")
        try write("broken", "---\nname: other-name\ndescription: x\n---\n")
        try write("Bad_Name", "---\nname: Bad_Name\ndescription: x\n---\n")
        let index = library.index()
        #expect(index.map(\.name) == ["organize-downloads", "tidy-desk", "weekly-review"])
        #expect(index.last?.description == "My own review.")
        #expect(library.skill(named: "weekly-review")?.origin == .user)
        #expect(index.allSatisfy { $0.trusted })
    }

    @Test func agentWrittenSkillsLoadAsUntrusted() async throws {
        let env = try TestEnv()
        env.registry.register(SkillTools.all(library))
        try write("from-agent", "---\nname: from-agent\ndescription: Made by the agent.\nsource: agent\n---\nDo \u{200B}this.")
        let agentSkill = await env.executor.execute(name: "skills.load", input: ["name": "from-agent"], caller: .agent(runId: "r"))
        #expect(agentSkill.untrusted)
        #expect(agentSkill.modelText.contains("Do this."))
        let bundled = await env.executor.execute(name: "skills.load", input: ["name": "organize-downloads"], caller: .agent(runId: "r"))
        #expect(!bundled.untrusted)
        let list = await env.executor.execute(name: "skills.list", input: [:], caller: .agent(runId: "r"))
        #expect(list.untrusted)
        let missing = await env.executor.execute(name: "skills.load", input: ["name": "nope"], caller: .agent(runId: "r"))
        #expect(!missing.isOK)
    }

    @Test func createWritesSourceAndShowsFullTextForApproval() async throws {
        let env = try TestEnv()
        env.registry.register(SkillTools.all(library))
        let instructions = "1. Open the calendar.\n2. List tomorrow's meetings."
        let answered = env.autoAnswer(.allowOnce)
        let outcome = await env.executor.execute(name: "skills.create", input: [
            "name": "plan-tomorrow", "description": "Plan tomorrow.", "instructions": .string(instructions),
        ], caller: .agent(runId: "r"))
        #expect(outcome.isOK)
        let request = try #require(await answered.value)
        #expect(request.risk == .medium)
        guard case .text(let text) = request.details else { Issue.record("expected the full text in the approval"); return }
        #expect(text.contains(instructions))

        let skill = try #require(library.skill(named: "plan-tomorrow"))
        #expect(skill.source == "agent")
        #expect(!skill.trusted)
        #expect(skill.instructions == instructions)

        // A different text never matches an "always" grant made for this one.
        let tool = try #require(env.registry.tool(named: "skills.create"))
        #expect(tool.scope(for: ["name": "a", "description": "b", "instructions": "c"]).text
                != tool.scope(for: ["name": "a", "description": "b", "instructions": "c; and more"]).text)
    }

    @Test func externalAndExtensionCallersCannotCreateSkills() async throws {
        let tool = try #require(SkillTools.all(library).first { $0.spec.name == "skills.create" })
        #expect(!tool.spec.external)
        for caller in [Caller.external(client: "codex"), .extension(id: "dev.x.y")] {
            await #expect(throws: UserFacingError.self) {
                try await tool.run(["name": "x", "description": "y", "instructions": "z"], context: ToolContext(caller: caller, now: Date()))
            }
        }
        #expect(library.skill(named: "x") == nil)
        let user = try await tool.run(["name": "mine", "description": "d", "instructions": "i"], context: ToolContext(caller: .user, now: Date()))
        #expect(user.text.contains("mine"))
        #expect(library.skill(named: "mine")?.trusted == true)
    }

    @Test func createRefusesBadInputAndExistingNames() throws {
        #expect(throws: UserFacingError.self) { try library.create(name: "Bad Name", description: "d", instructions: "i", source: "user") }
        #expect(throws: UserFacingError.self) { try library.create(name: "ok", description: "", instructions: "i", source: "user") }
        #expect(throws: UserFacingError.self) {
            try library.create(name: "ok", description: "d", instructions: String(repeating: "x", count: 20_001), source: "user")
        }
        #expect(throws: UserFacingError.self) { try library.create(name: "weekly-review", description: "d", instructions: "i", source: "user") }
        let s = try library.create(name: "ok", description: "Line one\nline \"two\"", instructions: "Do it.", source: "routine:r1")
        #expect(s.description == #"Line one line "two""#)
        #expect(s.source == "routine:r1")
    }

    @Test func deleteMovesToTrashAndUndoRestores() async throws {
        let env = try TestEnv()
        env.registry.register(SkillTools.all(library))
        try library.create(name: "old-habit", description: "d", instructions: "i", source: "user")
        let outcome = await env.executor.execute(name: "skills.delete", input: ["name": "old-habit"], caller: .user)
        #expect(outcome.isOK)
        #expect(library.skill(named: "old-habit") == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: trashDir.path).count == 1)
        #expect(try await env.executor.undo.undo(outcome.activity.id) != nil)
        #expect(library.skill(named: "old-habit") != nil)

        #expect(throws: UserFacingError.self) { try library.delete(name: "organize-downloads") }
    }
}
