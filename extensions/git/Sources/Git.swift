import Foundation
import SidefolkExtensionKit

/// Git, deliberately small: https remotes only (no SSH keys, no saved passwords, so public repositories), no
/// hooks, no submodules, no system or global configuration. Sidefolk finds git on this Mac, names it in
/// SIDEFOLK_EXEC_GIT, and opens a folder of the person's only for the call that names it.
enum Git {
    static let program = ProcessInfo.processInfo.environment["SIDEFOLK_EXEC_GIT"] ?? ""

    /// Settings every command gets, whatever a repository's own configuration says: nothing runs but git and its
    /// https helper (the sandbox enforces that too), and nothing asks for a password it can't get.
    static let safe = ["-c", "core.hooksPath=/dev/null", "-c", "core.fsmonitor=false", "-c", "credential.helper=",
                       "-c", "protocol.allow=never", "-c", "protocol.https.allow=always", "-c", "submodule.recurse=false"]

    static var environment: [String: String] {
        ProcessInfo.processInfo.environment.merging([
            "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_TERMINAL_PROMPT": "0", "GIT_ASKPASS": "",
            "SSH_ASKPASS": "", "GIT_PROTOCOL_FROM_USER": "0", "LC_ALL": "C",
        ]) { _, new in new }
    }

    @discardableResult
    static func git(_ arguments: [String], timeout: TimeInterval = 60, check: Bool = true) throws -> Output {
        guard !program.isEmpty else { throw Problem("Sidefolk didn't pass the location of git, so nothing can run.") }
        let result = try run(program, safe + arguments, environment: environment, in: ProcessInfo.processInfo.environment["HOME"], timeout: timeout)
        if check, result.status != 0 { throw Problem(explain(result.err)) }
        return result
    }

    /// Git's error, in words that say what to do; the last line of its own output otherwise.
    static func explain(_ stderr: String) -> String {
        let text = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = text.lowercased()
        if ["could not read username", "authentication failed", "terminal prompts disabled"].contains(where: lowered.contains) {
            return "It needs a sign-in: the repository is private, or the address is wrong. Git here can only reach public "
                + "repositories, because it can't use your saved passwords or keys."
        }
        if lowered.contains("repository not found") || (lowered.contains("not found") && lowered.contains("http")) {
            return "There's no public repository at that address."
        }
        if lowered.contains("could not resolve host") { return "Couldn't reach that address: check it, and the internet connection." }
        if lowered.contains("transport"), lowered.contains("not allowed") {
            return "This repository's remote isn't an https address (it may use SSH, which needs your keys). Git here only reaches https remotes."
        }
        if lowered.contains("not possible to fast-forward") || lowered.contains("diverging branches") {
            return "The branch and its remote have both moved on, so it can't simply be brought up to date. Nothing changed; merge or rebase it yourself."
        }
        if lowered.contains("would be overwritten") { return "Some changed files would be overwritten. Nothing changed; commit or stash them first." }
        if lowered.contains("no tracking information") { return "This branch doesn't follow a branch on a remote, so there's nothing to pull." }
        if lowered.contains("not a git repository") { return "That folder isn't a Git repository." }
        let last = text.split(separator: "\n").last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return last.map { String($0.trimmingCharacters(in: .whitespaces).prefix(300)) } ?? "Git failed without saying why."
    }

    static func checkURL(_ url: String) throws -> URLComponents {
        guard let parts = URLComponents(string: url), parts.scheme == "https", parts.host?.isEmpty == false, !url.hasPrefix("-"),
              !url.contains(where: \.isWhitespace) else {
            throw Problem("Only https addresses can be cloned here, like https://github.com/owner/project.")
        }
        guard parts.user == nil, parts.password == nil else {
            throw Problem("Leave sign-in details out of the address; Git here only clones public repositories.")
        }
        return parts
    }

    static func headLine(_ repository: String) throws -> String {
        let out = try git(["-C", repository, "log", "-1", "--pretty=format:%h\u{1F}%s\u{1F}%ar"], check: false).out
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !out.isEmpty else { return "no commits yet" }
        let f = out.components(separatedBy: "\u{1F}") + ["", ""]
        return "latest commit \(f[0]) “\(f[1].prefix(120))” (\(f[2]))"
    }

    static func branch(_ repository: String) throws -> String {
        let name = try git(["-C", repository, "rev-parse", "--abbrev-ref", "HEAD"], check: false).out.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "an unborn branch" : name
    }

    // MARK: Tools

    static func clone(_ url: String, into raw: String) throws -> String {
        let parts = try checkURL(url)
        let destination = try Paths.full(raw)
        let parent = (destination as NSString).deletingLastPathComponent
        guard Paths.exists(parent, folder: true) else {
            throw Problem("\(Paths.show(parent)) doesn't exist yet. Create it first, then clone into \(Paths.show(destination)).")
        }
        guard !Paths.exists(destination) else { throw Problem("\(Paths.show(destination)) already exists. Choose a new folder name.") }
        try git(["clone", "--quiet", "--", url, destination], timeout: 290)
        var name = parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if name.hasSuffix(".git") { name = String(name.dropLast(4)) }
        return "Cloned \(name.isEmpty ? parts.host ?? url : name) into \(Paths.show(destination)): branch \(try branch(destination)), "
            + "\(try headLine(destination))."
    }

    static func status(_ raw: String) throws -> String {
        let repository = try Paths.full(raw)
        let out = try git(["--no-optional-locks", "-C", repository, "status", "--porcelain=v2", "--branch", "--untracked-files=normal"]).out
        var head = "", upstream = "", ahead = 0, behind = 0
        var tracked = 0, staged = 0, untracked = 0, conflicted = 0, names: [String] = []
        // Porcelain v2: "1 XY … path", "2 XY … score path<TAB>old path", "u XY … path", "? path".
        for line in out.split(separator: "\n").map(String.init) {
            if line.hasPrefix("# branch.head ") {
                head = String(line.dropFirst(14))
            } else if line.hasPrefix("# branch.upstream ") {
                upstream = String(line.dropFirst(18))
            } else if line.hasPrefix("# branch.ab ") {
                let ab = line.dropFirst(12).split(separator: " ")
                ahead = Int(ab.first ?? "") ?? 0
                behind = -(Int(ab.last ?? "") ?? 0)
            } else if line.hasPrefix("1 ") || line.hasPrefix("2 ") {
                tracked += 1
                if line.split(separator: " ", maxSplits: 2)[1].first != "." { staged += 1 }
                let path = line.hasPrefix("2 ") ? String(line.split(separator: "\t")[0]) : line
                names.append(path.split(separator: " ", maxSplits: line.hasPrefix("2 ") ? 9 : 8, omittingEmptySubsequences: false).last.map(String.init) ?? "")
            } else if line.hasPrefix("u ") {
                conflicted += 1
                names.append(line.split(separator: " ", maxSplits: 10, omittingEmptySubsequences: false).last.map(String.init) ?? "")
            } else if line.hasPrefix("? ") {
                untracked += 1
                names.append(String(line.dropFirst(2)))
            }
        }
        var place = "\(Paths.show(repository)) on \(head == "(detached)" ? "a detached HEAD" : head)"
        if !upstream.isEmpty {
            place += ahead != 0 || behind != 0 ? ", \(ahead) ahead and \(behind) behind \(upstream) (as of the last fetch)"
                : ", even with \(upstream) (as of the last fetch)"
        }
        guard !names.isEmpty else { return place + ". Nothing changed." }
        var counts: [String] = []
        if tracked > 0 { counts.append("\(tracked) changed (\(staged) staged)") }
        if conflicted > 0 { counts.append("\(conflicted) with conflicts") }
        if untracked > 0 { counts.append("\(untracked) new and untracked") }
        let shown = names.prefix(15).joined(separator: ", ") + (names.count > 15 ? ", and \(names.count - 15) more" : "")
        return "\(place). \(counts.joined(separator: "; ")): \(shown)."
    }

    static func pull(_ raw: String) throws -> String {
        let repository = try Paths.full(raw)
        let before = try git(["-C", repository, "rev-parse", "HEAD"]).out.trimmingCharacters(in: .whitespacesAndNewlines)
        try git(["-C", repository, "pull", "--ff-only", "--no-rebase", "--quiet"], timeout: 290)
        let after = try git(["-C", repository, "rev-parse", "HEAD"]).out.trimmingCharacters(in: .whitespacesAndNewlines)
        guard before != after else { return "\(Paths.show(repository)) on \(try branch(repository)) is already up to date." }
        let count = try git(["-C", repository, "rev-list", "--count", "\(before)..\(after)"]).out.trimmingCharacters(in: .whitespacesAndNewlines)
        return "Pulled \(count) new commit\(count == "1" ? "" : "s") into \(Paths.show(repository)) on \(try branch(repository)); \(try headLine(repository))."
    }

    static func log(_ raw: String, count: Int) throws -> String {
        let repository = try Paths.full(raw)
        let out = try git(["-C", repository, "log", "-n", "\(count)", "--pretty=format:%h\u{1F}%an\u{1F}%ar\u{1F}%s"]).out
        let lines = out.split(separator: "\n").map { row -> String in
            let f = row.components(separatedBy: "\u{1F}") + ["", "", ""]
            return "\(f[0])  \(f[2])  \(f[1]): \(f[3].prefix(160))"
        }
        guard !lines.isEmpty else { return "\(Paths.show(repository)) has no commits yet." }
        return "Latest commits on \(try branch(repository)) in \(Paths.show(repository)):\n" + lines.joined(separator: "\n")
    }
}
