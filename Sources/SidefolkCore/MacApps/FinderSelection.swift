import Darwin
import Foundation
import Synchronization

/// What's selected in Finder, asked only when the person presses the ring's shortcut with Finder in front (D152). A child process, as for
/// every Apple Event here (`OsascriptRunner`): Finder or macOS's question about it can take their time, and must never freeze the app.
public enum FinderSelection {
    public enum Answer: Sendable, Equatable {
        case files([String])
        case tooMany
        case notAllowed
        case failed
    }

    /// One more than a drop can carry is all it needs to know. Counted first, since asking for each file's address is an event each.
    static let program = """
    const selected = Application("com.apple.finder").selection();
    selected.length > \(ExtensionOutputs.maxFiles) ? "too many" : JSON.stringify(selected.map(item => item.url()))
    """

    /// Long enough for the person to answer macOS's question the first time.
    static let deadline: Duration = .seconds(60)

    /// Said once, before the first read: macOS's question says "control Finder", which sounds like more than this is for (SECURITY T49).
    public static func wordsBeforeFirstRead(_ defaults: UserDefaults = .standard) -> String? {
        let said = "fileRing.finderExplained"
        guard !defaults.bool(forKey: said) else { return nil }
        defaults.set(true, forKey: said)
        return String(localized: "macOS may ask to let Sidefolk control Finder. Sidefolk uses that only to read what you selected.", comment: "The ring's shortcut, said once before macOS's question about Finder")
    }

    public static func read() async -> Answer {
        guard let child = try? PipedChild.spawn(OsascriptRunner.executable, arguments: ["-l", "JavaScript", "-"], environment: OsascriptRunner.environment(),
                                                cwd: NSTemporaryDirectory()) else { return .failed }
        let timer = Task {
            try await Task.sleep(for: deadline)
            child.signalGroup(SIGKILL)
        }
        defer { timer.cancel() }
        _ = child.write(program)
        child.closeInput()
        let reader = DescriptorLineReader(fd: child.output, limit: 1 << 20)
        var printed = ""
        while let item = await reader.next() {
            if case .line(let bytes) = item { printed += String(decoding: bytes, as: UTF8.self) }
        }
        guard case .exited(0) = await child.wait() else {
            return OsascriptRunner.errorNumber(in: await child.stderr()) == -1743 ? .notAllowed : .failed
        }
        return answer(printed)
    }

    /// `file:///` addresses, as Finder gives them. Anything else, like a selected server, isn't a file here.
    static func answer(_ printed: String) -> Answer {
        let text = printed.trimmingCharacters(in: .whitespacesAndNewlines)
        if text == "too many" { return .tooMany }
        guard let list = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [Any] else { return .failed }
        return .files(list.compactMap { ($0 as? String).flatMap(URL.init(string:)) }.filter(\.isFileURL).map(\.path))
    }
}
