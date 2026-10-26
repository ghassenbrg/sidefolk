import Foundation

/// How the exposed tools read to other agents. Sidefolk's own descriptions are written for its own
/// agent, which may create collections, set critical alerts, read web values and see every watcher;
/// another agent following them would try what Guard then refuses, so it gets words and schemas that
/// say what it can actually do (T4). Model-facing text, so English (D28).
extension ExternalToolPolicy {
    /// The spec an external agent sees: its own description and schema, and reading tools raised to at
    /// least medium so Guard asks every time.
    public static func externalSpec(_ spec: ToolSpec) -> ToolSpec {
        var spec = spec
        if asking.contains(spec.name) { spec.risk = max(spec.risk, .medium) }
        if let text = descriptions[spec.name] { spec.description = text }
        switch spec.name {
        case "notes.save":
            spec.inputSchema = editing(spec.inputSchema, removing: ["collection_kind"]) { props in
                props["collection"] = Schema.string("One of the user's existing projects, topics or lists, e.g. “Pockito” or “Shopping”. Leave out for the Inbox.")
            }
        case "reminders.create", "watch.create":
            spec.inputSchema = editing(spec.inputSchema) { props in
                // Critical breaks through quiet mode with sound; only the user's own click sets it (T24).
                if props["level"] != nil {
                    props["level"] = Schema.string("How loudly to tell the user (default attention).", enum: ["gentle", "attention"])
                }
                // Command watchers are the user's alone (T9), whatever kinds watch.create grows.
                if case .object(var kind)? = props["kind"], case .array(let values)? = kind["enum"] {
                    kind["enum"] = .array(values.filter { !($0.stringValue ?? "").lowercased().contains("command") })
                    props["kind"] = .object(kind)
                }
            }
        case "watch.report":
            spec.inputSchema = Schema.object([
                "source": Schema.string("Always metric: a value of this Mac.", enum: ["metric"]),
                "metric": Schema.string("Which value.", enum: Metric.allCases.map(\.rawValue)),
                "every_seconds": Schema.number("Seconds between readings, as the user asked (5 at the fastest)."),
                "until": Schema.string("When to stop, in the user's words (\"6pm\", \"in 2 hours\"). Leave out for the default end."),
                "title": Schema.string("Short name (optional), like \"CPU\"."),
            ], required: ["source", "metric"])
            // A value of this Mac reaches no server: what matters is whether watching and system information are on.
            spec.capabilities = [.watch, .system]
        default:
            break
        }
        return spec
    }

    static let descriptions: [String: String] = [
        "notes.save": """
            Save a note, idea, task or link in the user's Sidefolk notebook. The first line of `text` becomes the title, \
            the rest the body. It goes to the Inbox unless `collection` names one of the user's existing projects, topics or \
            lists; other agents can't create collections, so when the name isn't found, save to the Inbox or ask the user to \
            create it. Use kind task for to-dos and list items. Notes you save are tagged with your name. Never save passwords, \
            API keys, tokens or other secrets.
            """,
        "reminders.create": """
            Remind the user about something at a time: a bubble on their desktop with Done and Snooze, kept across restarts. \
            `when` takes plain language ("in 20 minutes", "tomorrow at 9", "friday 3pm", "every weekday at 9", "every 30 \
            minutes until 6pm") or ISO 8601. Set one only when the user asked and the time is clear. A reminder repeats at \
            most once a minute. Keep the id from the result: reminders_cancel takes it.
            """,
        "reminders.cancel": """
            Cancel a reminder you set earlier, by the id reminders_create returned. A repeating reminder stops repeating. \
            Reminders the user or other apps set can't be cancelled from here.
            """,
        "watch.create": """
            Tell the user when something happens, even while they're busy. kind: url_change (a public web page changed, or \
            now says or stops saying some words; checked every 5 minutes at most), site_status (a public website went down \
            or came back up), file_appears, file_changes and folder_new_file (only inside folders the user shared with \
            Sidefolk; target is the full path), process_exits (a program on this Mac quit; target is its name or process \
            number). Addresses on this Mac or the local network (localhost, 192.168.x.x, .local) are refused: ask the user to \
            set those up in Sidefolk. Your watchers stop on their own after a day; watch_stop ends one sooner.
            """,
        "watch.report": """
            Show a live value of this Mac beside the user's companion, updated in place (not a notification): cpu, memory, \
            battery, disk or network, every few seconds (5 s at the fastest; a faster request is raised and the result says \
            so). It stops on its own after an hour when it reads more often than once a minute, otherwise after a day, or at \
            `until`. watch_stop ends it sooner.
            """,
        "watch.list": "List the watchers and live values you started, with their ids and state. Other apps' and the user's don't show.",
        "watch.stop": "Stop one of your watchers or live values, by its id (or its title).",
        "notify.user": """
            Show the user a short message on their desktop: a task finished, failed, or needs them. Use gentle (the default) \
            for news and attention only when they should look now. Sidefolk spaces notices out and holds them during quiet \
            mode, full screen or while the user is away; the result says when it was held. Send one notice per event and \
            never repeat one.
            """,
        "ask.user": """
            Ask the user a short question on their desktop and wait for the answer, for a decision you need while they may be \
            away from your chat ("Push to main now?"). Offer 2 to 4 answer buttons when the choices are known; leave options \
            out to let them type. Returns the chosen option, what they typed, or "no answer" after the timeout; with no answer, \
            don't do what you asked about.
            """,
        "status": "Whether Sidefolk is running, and how many agent sessions, jobs, reminders and watches it keeps track of (counts only).",
        "notes.search": "Full-text search over the user's notes, ideas, tasks and links. The user is asked to allow each search.",
        "notes.list": "List the user's newest notes, ideas, tasks and links, optionally for one collection, kind or status. The user is asked to allow each read.",
        "reminders.list": "List the user's upcoming reminders, soonest first, with their ids. The user is asked to allow each read.",
        "agenda.today": """
            What's on the user's plate today: today's reminders with their times, open tasks and how many watches are \
            running. The user is asked to allow each read.
            """,
    ]

    /// A copy of an object schema with some properties removed (and from `required`), then `change` applied
    /// to the rest.
    private static func editing(_ schema: JSONValue, removing removed: Set<String> = [],
                                _ change: (inout [String: JSONValue]) -> Void = { _ in }) -> JSONValue {
        guard case .object(var root) = schema, case .object(var props)? = root["properties"] else { return schema }
        for key in removed { props[key] = nil }
        change(&props)
        root["properties"] = .object(props)
        if case .array(let required)? = root["required"] {
            root["required"] = .array(required.filter { !removed.contains($0.stringValue ?? "") })
        }
        return .object(root)
    }
}
