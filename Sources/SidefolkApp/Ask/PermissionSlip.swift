import SidefolkCore
import SwiftUI

/// Guard's question as a permission slip (D84, rebuilding D71's card): a strip that says who asks in a calm or firm
/// tone, Guard's face, one sentence of what would happen, what it touches as chips, and two answers. "Always…" waits
/// in Allow's menu, the exact request is folded. Firm slips never take Return: ⌘Return or a click (D58, D84). For a
/// moment after it appears its buttons ignore what reaches them, so a key or click meant for something else can't answer
/// it; they look as they are, the main one the deep aqua it will be (phase 3's rule for every approval).
struct PermissionSlip: View {
    var request: ApprovalRequest
    /// The extension whose tool asks, shown by its icon and name.
    var look: ExtensionLook?
    /// Who Sidefolk is to the person ("Mochi"), for "Mochi wants to".
    var companionName: String
    /// On its own above the companion (glass, with a tail), or inside Ask among the results (a card).
    var tail: SidecardTail?
    var standalone = false
    /// Opens with the exact request unfolded.
    var exactOpen = false
    /// Whether its buttons take Return, ⌘Return and Escape. Today's queue answers from the keyboard per row instead, so a
    /// Return typed into a field on the same page can never approve anything.
    var keys = true
    /// Today's queue: the row the keyboard is on.
    var focused = false
    var decide: (ApprovalDecision) -> Void
    var changeMode: () -> Void
    @State private var armed = false
    @State private var exact = false

    var body: some View {
        if standalone {
            SidecardSurface(tail: tail, padding: 0) { content.clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)) }
                .frame(width: Theme.Size.sidecardMax)
        } else {
            content
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .cardSurface()
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .strokeBorder(focused ? Theme.accent : .clear, lineWidth: 2)
                }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidecardStrip(tone: request.slipTone == .calm ? .calm : .firm, text: Text(verbatim: stripText))
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack(alignment: .top, spacing: Theme.Space.m) {
                    if let look { ExtensionBadge(look: look, size: Theme.Size.avatar) } else { FolkAvatar(name: "guard", size: Theme.Size.avatar) }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(asker) wants to", comment: "Above a permission slip's title: who asks (“Mochi wants to”, “Codex wants to”)")
                            .font(Theme.Font.callout).foregroundStyle(Theme.inkMuted)
                        Text(verbatim: request.title).font(Theme.Font.bubbleTitle).foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if request.summary != request.title {
                            // An extension's or another agent's request shows whole: what's clipped here could still run (D160).
                            let whole = request.asker != nil || request.caller.kind == "external"
                            Text(verbatim: whole ? request.summary.split(whereSeparator: \.isNewline).joined(separator: " ") : request.summary)
                                .font(Theme.Font.callout).foregroundStyle(Theme.inkMuted).lineLimit(whole ? nil : 3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let ends = request.expiresAt {
                            Text("Waits until \(TimeFormat.clock(ends, calendar: .autoupdatingCurrent))",
                                 comment: "On a permission slip: when it stops waiting (“Waits until 16:27”)")
                                .font(Theme.Font.callout).foregroundStyle(Theme.inkFaint)
                        }
                    }
                }
                ButtonRow(spacing: Theme.Space.xs) {
                    TouchChip(Touch(request.effect))
                    ForEach(Array(extraChips.enumerated()), id: \.offset) { _, chip in Chip(text: chip, tone: .neutral) }
                    if carriesExact {
                        Button { withAnimation(Theme.Motion.ease(0.2)) { exact.toggle() } } label: {
                            Label { Text("Exact request", comment: "A permission slip: shows the request exactly as it would run") } icon: {
                                Image(systemName: exact ? "chevron.up" : "chevron.down")
                            }
                            .labelStyle(TrailingIcon())
                        }
                        .buttonStyle(.sf(.quiet, size: .small))
                        .accessibilityAddTraits(exact ? .isSelected : [])
                    }
                }
                if exact { exactRequest }
                if sharesFolder {
                    Text("It stays shared until you remove it in Settings › Trust.", comment: "On a permission slip that asks to share a folder: the main button remembers it")
                        .font(Theme.Font.callout).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
                }
                if let alwaysNote {
                    Text(verbatim: alwaysNote).font(Theme.Font.callout).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: Theme.Space.s) {
                    if keys, !request.takesReturn {
                        HStack(spacing: 5) {
                            KeyHint("⌘↩")
                            Text("allows", comment: "Beside a ⌘↩ key hint on a permission slip that Return never answers")
                                .font(Theme.Font.callout).foregroundStyle(Theme.inkMuted)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    Spacer(minLength: Theme.Space.s)
                    Button { answer(.deny) } label: { Text("Not now", comment: "A permission slip's button: say no this time") }
                        .buttonStyle(.sf(.secondary, size: .sidecard))
                        .keyboardShortcut(keys ? .cancelAction : nil)
                    allow
                }
            }
            .padding(Theme.Space.l)
        }
        // Text the person has to read in full (a plan, a skill's instructions) doesn't wait to be unfolded.
        .onAppear {
            if exactOpen { exact = true }
            if case .text = request.details { exact = true }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(800))
            armed = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Permission request: \(request.title)"))
    }

    /// Allow, with "Always…" and "for this request" in its menu when the mode permits them (b08).
    private var allow: some View {
        HStack(spacing: 1) {
            // A folder is shared for good by the main button (D185): the person is asked once, not again for every call in it.
            let button = Button { answer(sharesFolder ? .allowAlways : .allowOnce) } label: {
                if sharesFolder { Text("Share folder", comment: "A permission slip's main button when it asks to share a folder: remembered until removed in Trust") }
                else { Text("Allow", comment: "A permission slip's main button") }
            }
            .buttonStyle(.sf(.primary, size: .sidecard))
            if !keys {
                button
            } else if request.takesReturn {
                button.keyboardShortcut(.defaultAction)
            } else {
                button.keyboardShortcut(.return, modifiers: .command)
            }
            if request.canAlways || request.canAllowForRequest || request.canKeepReading || request.canAllowAgentsToRead {
                Menu {
                    Button { answer(.allowOnce) } label: { if sharesFolder { Text("Just this time") } else { Text("Allow once") } }
                    if request.canKeepReading {
                        Button { answer(.keepReading) } label: { Text("Allow, and read a few pages it links to without asking", comment: "In Allow's menu when the AI reads a page. For this conversation: an hour and twelve pages at most, and it stops if the AI uses anything else") }
                    }
                    if request.canAllowAgentsToRead {
                        Button { answer(.allowAgentsToRead) } label: { Text("Allow, and let other agents read my notes and reminders", comment: "In Allow's menu when another agent reads the notebook: sets “Read your notes and reminders” to Allow in Trust") }
                    }
                    if request.canAlways, !sharesFolder {
                        Button { answer(.allowAlways) } label: { Text(isFolderCard ? "Share folder" : alwaysTitle) }
                    } else if request.canAllowForRequest {
                        Button { answer(.allowForRequest) } label: { Text("Allow for this request") }
                    }
                    Divider()
                    Button { changeMode() } label: { Text("Change how \(companionName) asks…", comment: "In Allow's menu on a permission slip: opens the approval settings") }
                } label: {
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(.sf(.primary, size: .sidecard))
                .fixedSize()
                .accessibilityLabel(Text("More ways to allow", comment: "VoiceOver: the menu beside Allow on a permission slip"))
            }
        }
    }

    /// The card asks to share a folder: its main button remembers it, and "Just this time" is in the menu.
    /// Not in Ask every time, where the person chose to be asked each time, and not when the request read outside content first: then a page may be steering which folder, so the main button is "Allow" (this
    /// call) and sharing for good is a deliberate choice in the menu.
    private var sharesFolder: Bool {
        if case .folderAccess = request.details { request.canAlways && !request.tainted && request.mode != .askEveryTime } else { false }
    }

    private var isFolderCard: Bool {
        if case .folderAccess = request.details { true } else { false }
    }

    /// An answer counts once the slip has been in view for a moment.
    private func answer(_ decision: ApprovalDecision) {
        if armed { decide(decision) }
    }

    /// Who asks, in the name it gave or ours: another app's name is whatever it sent, so the strip says it is another app.
    private var asker: String {
        switch request.caller {
        case .external(let client): AgentFacingTools.displayName(client)
        // An extension's tool, whoever started it, is the extension acting ("Tea Timer wants to").
        case .extension, .command, .user, .agent, .routine: request.asker?.name ?? look?.name ?? companionName
        }
    }

    /// One sentence of why it asks, in the strip's tone.
    private var stripText: String {
        if let siteWarning { return siteWarning }
        if let reason = ApprovalReason(request) {
            return request.caller.kind == "external" ? String(localized: "Another app is asking. Only you can answer it.") : reason.text
        }
        switch request.caller {
        case .user, .command: return String(localized: "You asked for this a moment ago.")
        case .agent: return String(localized: "Part of what you asked \(companionName) to do.", comment: "A permission slip's calm strip; the companion's name")
        case .routine: return String(localized: "A routine you set up is asking.")
        case .extension: return request.firstParty ? String(localized: "One of Sidefolk's own extensions is asking.")
            : String(localized: "An extension Sidefolk hasn't checked is asking.")
        case .external: return String(localized: "Another app is asking. Only you can answer it.")
        }
    }

    /// The rest of what it touches, in words: how many files, the one site or service, read-only access.
    private var extraChips: [Text] {
        var chips: [Text] = []
        switch request.details {
        case .paths(let paths) where paths.count > 1: chips.append(Text("\(paths.count) files", comment: "A chip on a permission slip"))
        case .folderAccess(let folder, let write):
            chips.append(Text(verbatim: "\u{2066}\(FolderAccess.displayPath(folder))\u{2069}"))
            chips.append(write ? Text("Can change files", comment: "A chip on a permission slip for a folder") : Text("Read only", comment: "A chip on a permission slip for a folder"))
        default: break
        }
        if let site = request.site { chips.append(Text(verbatim: "\u{2066}\(site)\u{2069}")) }
        if let service = request.service { chips.append(Text("Only to \(service)", comment: "A chip on a permission slip: the one service it reaches (“Only to Open-Meteo”)")) }
        return chips
    }

    private var carriesExact: Bool {
        if request.input != nil { return true }
        if case .none = request.details { return false }
        // Text to read in full is open already, and stays open.
        if case .text = request.details { return false }
        return true
    }

    /// The only place for monospaced text (b08): exactly what would run, selectable.
    private var exactRequest: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            ApprovalDetails(details: request.details)
            if let input = request.input {
                ScrollView {
                    Text(verbatim: input).font(Theme.Font.mono).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 140)
            }
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
    }

    /// "Always allow" covers a whole site, never an address with details after "?" (D47): say so where it matters.
    private var alwaysNote: String? {
        guard request.canAlways, let site = request.site, carriesDetails else { return nil }
        return String(localized: "“Always allow” covers addresses on \(site) with nothing after “?”.")
    }

    private var alwaysTitle: String {
        if let site = request.site { return String(localized: "Always allow \(site)") }
        return String(localized: "Always allow")
    }

    /// Why a page Sidefolk wrote the address of asks after outside content (D47).
    private var siteWarning: String? {
        guard request.tainted, request.site != nil, request.effect == .usesInternet else { return nil }
        return carriesDetails
            ? String(localized: "This came up while reading outside content, so an address with details after “?” asks, even on a site you allowed. Check it carefully.")
            : String(localized: "This came up while reading outside content, so a site you haven't allowed asks each time. Check the address carefully.")
    }

    private var carriesDetails: Bool {
        guard case .url(let address) = request.details, let url = URL(string: address) else { return false }
        return url.query != nil || url.fragment != nil
    }
}

/// A label with its icon after the words ("Exact request ⌄").
private struct TrailingIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon.imageScale(.small)
        }
    }
}
