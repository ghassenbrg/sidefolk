import SidefolkCore
import SwiftUI

/// Every place in Settings that search can find and jump to (D84): rows and groups, by tab and section, in the words
/// the page shows. A row that uses `SettingsRow(_ key:)` takes its title and detail from here, so search and the page
/// never disagree; `.settingAnchor(_:)` marks where a jump lands.
enum SettingKey: String, CaseIterable, Hashable {
    // General
    case openAtLogin, askShortcut, cardShortcut, language, appUpdates, addonUpdates, channel, timesOfDay, welcome
    // Companion
    case chooseCompanion, presence, size, eyesFollow, folks, liveliness, sleep, gameTone, gameSounds
    // Attention
    case attentionMode, interruptions, quietHours, fullScreen, sounds, systemNotifications, hiddenNotifications, morningBrief
    // Brain
    case provider, lastRequest, voiceInput, spokenReplies, voice, speechModel
    // Trust
    case approvalMode, internet, folders, alwaysAllowed, unanswered, capabilities, agentAccess, location, calendar,
         keeps, history, exportData, diagnostics, debugLogging, deleteAll
    // Connections
    case claudeCode, codex, commandLine, otherApps
    // Add-ons
    case addons, addFolder, skills
    // Appearance
    case theme, lightOrDark, density, homeIcons, makeTheme

    var tab: SettingsTab {
        switch self {
        case .openAtLogin, .askShortcut, .cardShortcut, .language, .appUpdates, .addonUpdates, .channel, .timesOfDay, .welcome: .general
        case .chooseCompanion, .presence, .size, .eyesFollow, .folks, .liveliness, .sleep, .gameTone, .gameSounds: .companion
        case .attentionMode, .interruptions, .quietHours, .fullScreen, .sounds, .systemNotifications, .hiddenNotifications, .morningBrief:
            .attention
        case .provider, .lastRequest, .voiceInput, .spokenReplies, .voice, .speechModel: .brain
        case .approvalMode, .internet, .folders, .alwaysAllowed, .unanswered, .capabilities, .agentAccess, .location, .calendar,
             .keeps, .history, .exportData, .diagnostics, .debugLogging, .deleteAll: .trust
        case .claudeCode, .codex, .commandLine, .otherApps: .connections
        case .addons, .addFolder, .skills: .addons
        case .theme, .lightOrDark, .density, .homeIcons, .makeTheme: .appearance
        }
    }

    /// The eyebrow of the group the row sits in.
    var section: String {
        switch self {
        case .openAtLogin, .askShortcut, .cardShortcut, .language: String(localized: "Start", comment: "Settings › General: a group")
        case .appUpdates, .addonUpdates, .channel: String(localized: "Updates")
        case .timesOfDay, .welcome: String(localized: "Words for times", comment: "Settings › General: what morning, afternoon, evening mean")
        case .chooseCompanion: String(localized: "Choose a companion", comment: "Settings › Companion: a group")
        case .presence: String(localized: "Where it lives", comment: "Settings › Companion: always on the desktop, when needed, menu bar only")
        case .size, .eyesFollow, .folks: String(localized: "Look")
        case .liveliness, .sleep: String(localized: "How it behaves", comment: "Settings › Companion: a group")
        case .gameTone, .gameSounds: String(localized: "Games")
        case .attentionMode: String(localized: "Right now", comment: "Settings › Attention: Open, Focus or Quiet at this moment")
        case .interruptions: String(localized: "What may interrupt you", comment: "Settings › Attention: a group, how far each source may go")
        case .quietHours, .fullScreen: String(localized: "Quiet on its own", comment: "Settings › Attention: quiet hours and full-screen apps")
        case .sounds, .systemNotifications, .hiddenNotifications, .morningBrief:
            String(localized: "How things reach you", comment: "Settings › Attention: sounds, notifications, the morning brief")
        case .provider, .lastRequest: String(localized: "Who answers", comment: "Settings › Brain: a group")
        case .voiceInput, .spokenReplies, .voice, .speechModel: String(localized: "Voice")
        case .approvalMode: String(localized: "How much Sidefolk asks")
        case .internet, .folders, .alwaysAllowed, .unanswered, .capabilities:
            String(localized: "What Sidefolk may do")
        case .agentAccess: String(localized: "What other agents may do", comment: "Settings › Trust: a group")
        case .location, .calendar: String(localized: "What Sidefolk can see", comment: "Settings › Trust: location and calendar")
        case .keeps, .history, .exportData, .diagnostics, .debugLogging, .deleteAll: String(localized: "Your data")
        case .claudeCode, .codex, .commandLine, .otherApps: String(localized: "Connect your agents")
        case .addons, .addFolder, .skills: String(localized: "Your add-ons", comment: "Settings › Add-ons: the title of the page")
        case .theme, .makeTheme: String(localized: "Theme")
        case .lightOrDark, .density, .homeIcons: String(localized: "Look")
        }
    }

    var title: String {
        switch self {
        case .openAtLogin: String(localized: "Open at login")
        case .askShortcut: String(localized: "Ask shortcut")
        case .cardShortcut: String(localized: "Answer cards from the keyboard", comment: "Settings › General: the shortcut that brings the card beside the companion to the keyboard")
        case .language: String(localized: "Language")
        case .appUpdates: String(localized: "New versions of Sidefolk", comment: "Settings › Updates: what Sidefolk does about its own updates")
        case .addonUpdates: String(localized: "Update add-ons automatically")
        case .channel: String(localized: "Versions to offer")
        case .timesOfDay: String(localized: "Morning, afternoon and evening", comment: "Settings › General: the hours these words mean")
        case .welcome: String(localized: "Show the welcome again")
        case .chooseCompanion: String(localized: "Companion")
        case .presence: String(localized: "Where it lives", comment: "Settings › Companion: always on the desktop, when needed, menu bar only")
        case .size: String(localized: "Size")
        case .eyesFollow: String(localized: "Eyes follow the pointer")
        case .folks: String(localized: "Show folks on duty")
        case .liveliness: String(localized: "Liveliness")
        case .sleep: String(localized: "Sleep when you're away")
        case .gameTone: String(localized: "When it wins")
        case .gameSounds: String(localized: "Game sounds")
        case .attentionMode: String(localized: "Open, Focus or Quiet", comment: "Settings › Attention: the three ways things reach you")
        case .interruptions: String(localized: "What may interrupt you", comment: "Settings › Attention: a group, how far each source may go")
        case .quietHours: String(localized: "Quiet hours", comment: "Settings › Attention: quiet every night between two times")
        case .fullScreen: String(localized: "When an app is full screen", comment: "Settings › Attention")
        case .sounds: String(localized: "Sounds")
        case .systemNotifications: String(localized: "System notifications")
        case .hiddenNotifications: String(localized: "Use notifications while I'm hidden")
        case .morningBrief: String(localized: "Morning brief")
        case .provider: String(localized: "Who answers", comment: "Settings › Brain: a group")
        case .lastRequest: String(localized: "What Sidefolk sends")
        case .voiceInput: String(localized: "Voice input")
        case .spokenReplies: String(localized: "Spoken replies")
        case .voice: String(localized: "Voice")
        case .speechModel: String(localized: "Speech model")
        case .approvalMode: String(localized: "How much Sidefolk asks")
        case .internet: String(localized: "Using the internet")
        case .folders: String(localized: "Folders Sidefolk can use")
        case .alwaysAllowed: String(localized: "Always allowed")
        case .unanswered: String(localized: "If I don't answer")
        case .capabilities: String(localized: "What Sidefolk may do")
        case .agentAccess: String(localized: "What other agents may do", comment: "Settings › Trust: a group")
        case .location: String(localized: "Your location")
        case .calendar: String(localized: "Your calendar")
        case .keeps: String(localized: "What Sidefolk keeps")
        case .history: String(localized: "Keep conversations for")
        case .exportData: String(localized: "Export data")
        case .diagnostics: String(localized: "Diagnostics")
        case .debugLogging: String(localized: "Debug logging")
        case .deleteAll: String(localized: "Delete all Sidefolk data")
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .commandLine: String(localized: "sidefolk command", comment: "The `sidefolk` command-line tool; keep “sidefolk” as it is")
        case .otherApps: String(localized: "Other apps", comment: "Settings › Connections: apps that speak MCP besides Claude Code and Codex")
        case .addons: String(localized: "Your add-ons", comment: "Settings › Add-ons: the title of the page")
        case .addFolder: String(localized: "Added by you")
        case .skills: String(localized: "Skills")
        case .theme: String(localized: "Theme")
        case .lightOrDark: String(localized: "Light or dark", comment: "Settings › Appearance")
        case .density: String(localized: "Density", comment: "Settings › Appearance: comfortable or compact spacing")
        case .homeIcons: String(localized: "Icons in Home")
        case .makeTheme: String(localized: "Make your own theme", comment: "Settings › Appearance")
        }
    }

    /// One line of what it does: what search reads, and what a `SettingsRow(key)` shows unless told otherwise.
    var detail: String {
        switch self {
        case .openAtLogin: String(localized: "Sidefolk starts quietly when you log in.")
        case .askShortcut: String(localized: "Opens the Ask panel from any app.")
        case .cardShortcut: String(localized: "Only while a card waits beside the companion: ↩ answers, ⎋ puts it away, ↑↓ moves through the held ones.",
                                   comment: "Settings › General: what the card shortcut does")
        case .language: String(localized: "Typed requests are understood in English without AI; with AI, in any language.")
        case .appUpdates: String(localized: "A minute after Sidefolk starts and then once a day. It always asks before installing.")
        case .addonUpdates:
            String(localized: "Companions, themes and extensions from the gallery. An extension whose new version would be allowed to do more always waits for you to look first.")
        case .channel: String(localized: "Snapshots are test builds that come out before a release. Add-ons follow this too.")
        case .timesOfDay: String(localized: "What “tomorrow morning”, “this afternoon” and “this evening” mean. “Tonight” is 21:00.",
                                 comment: "Settings › General › Words for times")
        case .welcome: String(localized: "Replays the first hello on your desktop. Nothing is reset.")
        case .chooseCompanion: String(localized: "Who lives on your desktop, its name and what it wears.", comment: "Settings › Companion: search")
        case .presence: String(localized: "Always on the desktop, only when needed, or just the menu bar icon.", comment: "Settings › Companion: search")
        case .size: String(localized: "Small, medium or large on the desktop.", comment: "Settings › Companion: search")
        case .eyesFollow: String(localized: "A glance now and then, never a stare.")
        case .folks: String(localized: "Tempo, Scout and Byte sit beside the companion while a reminder, watch or agent is live.")
        case .liveliness: String(localized: "Minimal, balanced or lively: how often it moves on its own.", comment: "Settings › Companion: search")
        case .sleep: String(localized: "Naps after 10 minutes without input and wakes when you're back.")
        case .gameTone: String(localized: "How it takes a win in games: gently, cheekily or with a victory dance.", comment: "Settings › Companion: search")
        case .gameSounds: String(localized: "Soft sounds in games. Each game's speaker button turns its own on or off.")
        case .attentionMode: String(localized: "Focus holds whispers until it ends; Quiet lets through only what can't wait.",
                                    comment: "Settings › Attention")
        case .interruptions:
            String(localized: "Reminders, watches, commands, Claude Code, Codex, other apps, extensions, games and the companion: a card, a whisper, only in Today or off.",
                   comment: "Settings › Attention: search")
        case .quietHours: String(localized: "Every night. Reminders still come, silently; whispers wait for the morning.",
                                 comment: "Settings › Attention › Quiet hours")
        case .fullScreen: String(localized: "Presentations, games and video calls.", comment: "Settings › Attention › When an app is full screen")
        case .sounds: String(localized: "A soft chime for reminders and finished jobs.")
        case .systemNotifications: String(localized: "Reminders can reach you when the companion is hidden or you're in another Space.")
        case .hiddenNotifications: String(localized: "When the companion is tucked away or in the menu bar, reminders arrive as notifications.")
        case .morningBrief: String(localized: "Today's reminders, open tasks and watches in one bubble each morning.", comment: "Settings › Attention")
        case .provider: String(localized: "Claude Code, Codex, an API key, a model on this Mac or your own server.", comment: "Settings › Brain: search")
        case .lastRequest: String(localized: "Your notes and messages go only to the AI you chose, and only what's needed for the request.")
        case .voiceInput: String(localized: "Hold the shortcut and talk, release to send. Esc cancels.")
        case .spokenReplies: String(localized: "A short spoken answer, and how much to say.", comment: "Settings › Brain: search")
        case .voice: String(localized: "An AI voice, its speed and volume.", comment: "Settings › Brain: search")
        case .speechModel: String(localized: "What understands your voice, on this Mac.", comment: "Settings › Brain: search")
        case .approvalMode: String(localized: "Ask every time, once per kind, Auto, or Full access with an end.", comment: "Settings › Trust: search")
        case .internet: String(localized: "Pages and online services Sidefolk picks itself, and the sites you allowed.", comment: "Settings › Trust: search")
        case .folders: String(localized: "Sidefolk only touches files inside these folders. Anything it deletes goes to the Trash.")
        case .alwaysAllowed: String(localized: "Revoke any of these and Sidefolk asks again next time.")
        case .unanswered: String(localized: "When Sidefolk waits for your OK on something you asked for. Other agents' questions count as a no after two minutes.")
        case .capabilities: String(localized: "Commands, the internet, the clipboard, files, apps, Apple Notes and Reminders.", comment: "Settings › Trust: search")
        case .agentAccess: String(localized: "What Claude Code, Codex and other apps may save, change and read.", comment: "Settings › Trust: search")
        case .location: String(localized: "Your town for the weather and times, from your Mac or a place you choose.", comment: "Settings › Trust: search")
        case .calendar: String(localized: "Today, the morning brief and the AI may read your calendar.", comment: "Settings › Trust: search")
        case .keeps: String(localized: "Everything stays on this Mac. It's encrypted at rest by FileVault when FileVault is on.")
        case .history: String(localized: "Conversations with the AI, kept so you can follow up, then deleted.", comment: "Settings › Trust: search")
        case .exportData: String(localized: "Notes, reminders, watches with their history, and settings as one JSON file. No keys.")
        case .diagnostics: String(localized: "Logs and versions for a bug report, without your notes or messages.")
        case .debugLogging: String(localized: "More detail in the local log. Turn it off when you're done.")
        case .deleteAll: String(localized: "Notes, reminders, watches, history, logs and saved keys. This can't be undone.")
        case .claudeCode: String(localized: "Let Claude Code save notes, set reminders, watch and tell you when a session needs you.", comment: "Settings › Connections: search")
        case .codex: String(localized: "Let Codex save notes, set reminders, watch and tell you when a session needs you.", comment: "Settings › Connections: search")
        case .commandLine: String(localized: "Type sidefolk run -- npm test and hear when it ends.", comment: "Settings › Connections: search; keep the command as it is")
        case .otherApps: String(localized: "Cursor, VS Code, Zed or any app that speaks MCP: copy a setup snippet.", comment: "Settings › Connections")
        case .addons: String(localized: "Extensions, tool servers and skills: turn them on or off, update or remove them.", comment: "Settings › Add-ons: search")
        case .addFolder: String(localized: "Extensions from a folder and MCP servers you added.", comment: "Settings › Add-ons: search")
        case .skills: String(localized: "Skills are written instructions Sidefolk reads when a request needs them.")
        case .theme: String(localized: "A theme changes colours, type, spacing and corners. It can't run anything.")
        case .lightOrDark: String(localized: "Light or dark windows, or the same as your Mac.")
        case .density: String(localized: "Compact fits more rows in Home and Settings.", comment: "Settings › Appearance")
        case .homeIcons: String(localized: "Simple glyphs, or colourful tiles with each extension's own icon.")
        case .makeTheme: String(localized: "Start from a copy of Harbor in a folder, or use a theme folder you have. Sidefolk repaints each time you save.")
        }
    }

    var entry: SettingsSearch.Entry {
        SettingsSearch.Entry(id: rawValue, title: title, detail: detail, section: section)
    }

    static func find(_ query: String) -> [SettingKey] {
        SettingsSearch.find(query, in: allCases.map(\.entry)).compactMap { SettingKey(rawValue: $0.id) }
    }
}

/// Which tab is open, what is searched, and which setting a jump landed on: shared by the sidebar, the search
/// results and every page, so a result can open its tab and scroll to its row.
@MainActor @Observable
final class SettingsNavigation {
    var tab: SettingsTab = .general
    var query = ""
    /// The setting a jump is landing on; the page scrolls to it and it glows for a moment.
    var revealed: SettingKey?
    /// The result the arrow keys are on.
    var highlighted: SettingKey?

    var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    /// What the search found, grouped by tab as the results show them (the tab with the best match first), so the
    /// arrow keys go down the page.
    var results: [SettingKey] {
        let found = SettingKey.find(query)
        let tabs = found.map(\.tab).reduce(into: [SettingsTab]()) { tabs, tab in if !tabs.contains(tab) { tabs.append(tab) } }
        return tabs.flatMap { tab in found.filter { $0.tab == tab } }
    }

    /// Opens the tab the setting lives in and scrolls to it; the search is cleared.
    func jump(to key: SettingKey) {
        tab = key.tab
        query = ""
        highlighted = nil
        revealed = key
    }
}

extension EnvironmentValues {
    @Entry var settingsNavigation: SettingsNavigation?
}

/// Marks where a jump to `key` lands: an id to scroll to, and a short glow when it's the one asked for.
struct SettingAnchor: ViewModifier {
    var key: SettingKey
    @Environment(\.settingsNavigation) private var navigation
    @State private var glowing = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(Theme.accentSoft)
                    .opacity(glowing ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .id(key)
            .task(id: navigation?.revealed) {
                guard navigation?.revealed == key else { return }
                try? await Task.sleep(for: .milliseconds(200))
                withAnimation(.easeOut(duration: 0.2)) { glowing = true }
                try? await Task.sleep(for: .seconds(1.6))
                withAnimation(.easeOut(duration: 0.6)) { glowing = false }
            }
    }
}

extension View {
    func settingAnchor(_ key: SettingKey) -> some View { modifier(SettingAnchor(key: key)) }
}

struct OptionalSettingAnchor: ViewModifier {
    var key: SettingKey?

    func body(content: Content) -> some View {
        if let key { content.settingAnchor(key) } else { content }
    }
}

extension SettingsRow {
    /// A row whose title and detail come from the catalog, so search finds it in the same words; anchored for jumps.
    init(_ key: SettingKey, detail: Text? = nil, @ViewBuilder control: () -> Control) {
        self.init(title: Text(verbatim: key.title), detail: detail ?? Text(verbatim: key.detail), control: control)
        anchor = key
    }
}

extension SettingsToggle {
    /// A switch row in the catalog's words, anchored for search.
    init(_ key: SettingKey, isOn: Binding<Bool>) {
        self.init(title: Text(verbatim: key.title), detail: Text(verbatim: key.detail), isOn: isOn)
        anchor = key
    }
}
