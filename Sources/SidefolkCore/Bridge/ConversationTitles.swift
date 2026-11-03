import Foundation

/// What the agent's own app calls a conversation (D118), so two sessions in one project can be told apart. A hook's
/// payload has no title, but Claude Code writes one into its transcript and Codex into its session index.
///
/// **It reads for the title and nothing else.** Only the end of the file; only lines that declare a title are parsed at
/// all; nothing else is kept, logged or sent, and it never leaves this Mac. The path comes from a hook, so it's believed
/// only inside the agent's own folder, and never through a link. No title means the project's name, not a guess.
public struct ConversationTitles: Sendable {
    /// Claude Code's projects folder, and Codex's session index.
    let claudeProjects: URL
    let codexIndex: URL

    /// A title is near the end of a long transcript: Claude Code repeats it as the conversation goes on.
    static let tail = 256 * 1024
    static let longest = 80

    public init(claudeProjects: URL, codexIndex: URL) {
        self.claudeProjects = claudeProjects
        self.codexIndex = codexIndex
    }

    public init(locations: IntegrationLocations) {
        self.init(claudeProjects: locations.claudeSkills.deletingLastPathComponent().appendingPathComponent("projects", isDirectory: true),
                  codexIndex: locations.codexConfig.deletingLastPathComponent().appendingPathComponent("session_index.jsonl"))
    }

    public func title(agent: String, sessionId: String, transcriptPath: String?) -> String? {
        agent == "codex" ? codex(sessionId) : transcriptPath.flatMap(claude)
    }

    private func claude(_ path: String) -> String? {
        let file = URL(fileURLWithPath: path).standardizedFileURL
        guard file.pathExtension == "jsonl", file.resolvingSymlinksInPath().path.hasPrefix(claudeProjects.resolvingSymlinksInPath().path + "/"),
              let text = Self.end(of: file) else { return nil }
        // The person's own name for it wins over one the agent made up, wherever each is.
        var made: String?
        for line in text.split(separator: "\n").reversed() {
            if line.contains("\"type\":\"custom-title\""), let title = Self.field("customTitle", in: line) { return title }
            if made == nil, line.contains("\"type\":\"ai-title\"") { made = Self.field("aiTitle", in: line) }
        }
        return made
    }

    private func codex(_ sessionId: String) -> String? {
        guard let text = Self.end(of: codexIndex) else { return nil }
        for line in text.split(separator: "\n").reversed() where line.contains(sessionId) {
            guard (try? JSONValue.parse(String(line)))?.string("id") == sessionId else { continue }
            return Self.field("thread_name", in: line)
        }
        return nil
    }

    private static func field(_ key: String, in line: Substring) -> String? {
        guard let value = (try? JSONValue.parse(String(line)))?.string(key) else { return nil }
        let clean = value.displaySafe.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean.clipped(longest)
    }

    /// The file's end, if it's a plain file. Without blocking: a hook can name anything, and opening a pipe to read
    /// would wait for a writer for ever, on the actor every hook goes through.
    private static func end(of file: URL) -> String? {
        let fd = open(file.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
        let count = min(Int(info.st_size), tail)
        guard count > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: count)
        let read = pread(fd, &bytes, count, off_t(info.st_size) - off_t(count))
        guard read > 0 else { return nil }
        return String(decoding: bytes[0..<read], as: UTF8.self)
    }
}
