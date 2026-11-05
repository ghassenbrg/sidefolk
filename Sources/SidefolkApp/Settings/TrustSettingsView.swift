import AppKit
import SidefolkCore
import SwiftUI
import UniformTypeIdentifiers

/// Settings › Trust (D84, was Privacy & Permissions): how much Sidefolk asks, Full access with an end, the internet,
/// folders, what is always allowed and what may happen at all; what other agents may do; what Sidefolk can see (where
/// you are, D48, and your calendar, D57); and what it keeps, with the person's data (export, delete).
struct TrustSettingsView: View {
    var model: SettingsModel
    @State private var confirmingDelete = false
    @State private var confirmingHistory = false
    @State private var confirmingForget = false

    /// The capabilities a person can switch off, in the words the Settings page uses.
    private static let switches: [(Capability, LocalizedStringKey, LocalizedStringKey)] = [
        (.shell, "Running commands", "Shell commands, shown word for word before they run unless Full access is on."),
        (.network, "Internet access", "Fetching pages and checking sites."),
        (.clipboard, "Clipboard", "Reading and writing what you copied."),
        (.filesWrite, "Changing files", "Moving, renaming and creating files in your folders."),
        (.apps, "Opening apps and links", "Launching apps and opening web pages."),
        (.macApps, "Apple Notes and Reminders",
         "Reading them when you ask, and copying notes into the notebook. macOS asks you once for each app."),
    ]

    var body: some View {
        page.sheet(isPresented: $confirmingDelete) { DeleteAllSheet(model: model) }
            .sheet(isPresented: Binding(get: { model.backingUp }, set: { model.backingUp = $0 })) { BackupSheet(model: model) }
            .sheet(item: Binding(get: { model.restoreCandidate }, set: { model.restoreCandidate = $0 })) { RestoreSheet(model: model, candidate: $0) }
    }

    private var page: some View {
        SettingsPage {
            TrustHero(model: model)
            guardSettings
            AgentAccessGroup(model: model)
            Eyebrow(Text(verbatim: SettingKey.location.section)).padding(.leading, Theme.Space.xs).padding(.bottom, -Theme.Space.m)
            LocationGroup(model: model.location)
            CalendarGroup(model: model)
            keeps
            SettingsGroup(title: "History",
                          footer: "Conversations with the AI let you follow up (“and tomorrow too”) and read them again in Conversations, in Sidefolk's window. Then they're deleted.",
                          anchor: .history) {
                SettingsRow(title: "Keep conversations for") {
                    Picker("Keep conversations for", selection: Binding(
                        get: { model.settings.historyDays }, set: { days in model.update { $0.historyDays = days } }
                    )) {
                        ForEach(Array(Set([1, 7, 30, model.settings.historyDays])).sorted(), id: \.self) { days in
                            Text("\(days) days").tag(days)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsRow(title: "Conversation history") {
                    Button("Delete all history…") { confirmingHistory = true }
                        .buttonStyle(.sf(.secondary))
                        .disabled(model.storage?.exchanges == 0)
                }
            }
            .alert("Delete all conversation history?", isPresented: $confirmingHistory) {
                Button("Delete all history", role: .destructive) { Task { await model.deleteConversationHistory() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(DeleteHistoryWords.message)
            }
            data
        }
    }

    // MARK: What Sidefolk keeps

    private var keeps: some View {
        SettingsGroup(title: "What Sidefolk keeps", footer: "Everything stays on this Mac. It's encrypted at rest by FileVault when FileVault is on.",
                      anchor: .keeps) {
            if let s = model.storage {
                HStack(spacing: 0) {
                    count(s.notes, "Notes")
                    count(s.reminders, "Reminders")
                    count(s.watchers, "Watchers")
                    count(s.activity, "Activity")
                    count(s.exchanges, "Requests")
                }
                .padding(.vertical, Theme.Space.m)
                SettingsRow(title: Text("Data folder"),
                            detail: Text(verbatim: "\(FolderAccess.displayPath(s.dataFolder)) · \(Wording.bytes(s.databaseBytes))")) {
                    Button("Show in Finder") { model.services.revealDataFolder() }.buttonStyle(.sf(.secondary))
                }
            } else {
                InlineEmpty(text: "Counting…")
            }
        }
    }

    private func count(_ n: Int, _ label: LocalizedStringKey) -> some View {
        VStack(spacing: 2) {
            Text(n.formatted()).font(Theme.Font.heading).foregroundStyle(Theme.ink)
            Text(label).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: Folders

    private var folders: some View {
        SettingsGroup(title: "Folders Sidefolk can use",
                      footer: "Sidefolk only touches files inside these folders. Anything it deletes goes to the Trash.", anchor: .folders) {
            if model.folders.isEmpty {
                InlineEmpty(text: "No folders yet. Add one here, or allow one when Sidefolk asks.", systemImage: "folder")
            }
            ForEach(model.folders, id: \.path) { folder in
                HStack(spacing: Theme.Space.m) {
                    Image(systemName: "folder.fill").foregroundStyle(Theme.folkColor("byte")).accessibilityHidden(true)
                    Text(FolderAccess.displayPath(folder.path)).font(Theme.Font.body).foregroundStyle(Theme.ink)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: Theme.Space.s)
                    Picker("Access to \(FolderAccess.displayPath(folder.path))", selection: Binding(
                        get: { folder.access }, set: { access in Task { await model.setAccess(folder, access) } }
                    )) {
                        Text("Read only").tag(GrantedFolder.Access.read)
                        Text("Read and change").tag(GrantedFolder.Access.readwrite)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                    Button("Remove") { Task { await model.removeFolder(folder) } }.buttonStyle(.sf(.secondary))
                }
                .padding(.horizontal, Theme.Space.l)
                .padding(.vertical, Theme.Space.s + 2)
            }
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Button("Add folder…", action: addFolder).buttonStyle(.sf(.secondary))
                if let error = model.folderError { InlineError(error: error) }
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.m)
        }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = String(localized: "Share Folder")
        panel.message = String(localized: "Choose a folder Sidefolk may read and organize.")
        Task {
            let response: NSApplication.ModalResponse
            if let window = NSApp.keyWindow { response = await panel.beginSheetModal(for: window) } else { response = panel.runModal() }
            guard response == .OK, let url = panel.url else { return }
            await model.grantFolder(url)
        }
    }

    // MARK: Always allowed

    private var grants: some View {
        // Sites and extensions' services are listed under "Using the internet" (D47).
        let others = model.grants.filter { !InternetGrants.isInternet($0, extensions: model.extensions) }
        return SettingsGroup(title: "Always allowed", footer: "Revoke any of these and Sidefolk asks again next time. “Forget everything I allowed” takes back all of them.", anchor: .alwaysAllowed) {
            if others.isEmpty {
                InlineEmpty(text: "Nothing yet. When you choose “Always allow”, it's listed here.", systemImage: "checkmark.shield")
            }
            ForEach(others) { grant in
                HStack(spacing: Theme.Space.m) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.toolTitle(grant.tool)).font(Theme.Font.body).foregroundStyle(Theme.ink)
                        Text(grantDetail(grant)).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(2)
                    }
                    Spacer(minLength: Theme.Space.s)
                    Button("Revoke") { Task { await model.revoke(grant) } }.buttonStyle(.sf(.secondary))
                        .accessibilityLabel("Revoke \(model.toolTitle(grant.tool))")
                }
                .padding(.horizontal, Theme.Space.l)
                .padding(.vertical, Theme.Space.s + 2)
            }
            // Everything remembered in one click; folders are their own list above, and stay.
            if !others.isEmpty || !model.allowedForNow.isEmpty {
                Button("Forget everything I allowed…") { confirmingForget = true }.buttonStyle(.sf(.secondary))
                    .padding(.horizontal, Theme.Space.l)
                    .padding(.vertical, Theme.Space.m)
                    .confirmationDialog("Forget everything you allowed?", isPresented: $confirmingForget, titleVisibility: .visible) {
                        Button("Forget Everything", role: .destructive) { Task { await model.forgetEverythingAllowed() } }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Every “Always allow”, and everything allowed for now, is taken back and Sidefolk asks again. Folders you shared and sites listed under “Using the internet” stay.",
                             comment: "Settings › Trust: the question under “Forget everything you allowed?”")
                    }
            }
        }
    }

    // MARK: Allowed for now

    /// What the person said yes to for the length of a request or a conversation, while it holds: shown so it can be taken back.
    @ViewBuilder private var allowedNow: some View {
        if !model.allowedForNow.isEmpty {
            SettingsGroup(title: "Allowed for now", footer: "What you allowed for one request or conversation. Stop one and Sidefolk asks again.",
                          anchor: .allowedForNow) {
                ForEach(model.allowedForNow) { item in
                    HStack(spacing: Theme.Space.m) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: title(of: item)).font(Theme.Font.body).foregroundStyle(Theme.ink)
                            Text(verbatim: detail(of: item)).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(2)
                        }
                        Spacer(minLength: Theme.Space.s)
                        Button("Stop") { Task { await model.stopAllowing(item) } }.buttonStyle(.sf(.secondary))
                            .accessibilityLabel(Text("Stop allowing \(title(of: item))", comment: "VoiceOver: a button that takes back a yes that holds for now"))
                    }
                    .padding(.horizontal, Theme.Space.l)
                    .padding(.vertical, Theme.Space.s + 2)
                }
            }
        }
    }

    private func title(of item: AllowedForNow) -> String {
        switch item {
        case .tool(let name): model.toolTitle(name)
        case .readingOn: String(localized: "Reading the pages a page links to", comment: "Settings › Trust › Allowed for now: a yes to reading on")
        }
    }

    private func detail(of item: AllowedForNow) -> String {
        switch item {
        case .tool: String(localized: "for the request \(model.settings.companionName) is working on", comment: "Settings › Trust › Allowed for now: a tool allowed for one request")
        case .readingOn: String(localized: "in this conversation, for up to an hour", comment: "Settings › Trust › Allowed for now: reading on")
        }
    }

    private func grantDetail(_ g: Grant) -> String {
        var parts: [String] = []
        if let folder = g.scope.string("folder") { parts.append(String(localized: "in \(FolderAccess.displayPath(folder))")) }
        if let command = g.scope.string("command") { parts.append(String(localized: "exactly “\(command.clipped(60))”")) }
        if let host = g.scope.string("host") { parts.append(String(localized: "on \(host)", comment: "A web address it is allowed on: “on example.com”")) }
        if let ext = g.scope.string("extension") { parts.append(String(localized: "for \(ext)", comment: "An extension it is allowed for")) }
        let who = switch g.callerKind {
        case "agent": String(localized: "when \(model.settings.companionName) asks")
        case "external": String(localized: "when other agents ask")
        case "routine": String(localized: "in routines")
        case "extension": String(localized: "for extensions")
        default: String(localized: "for anyone")
        }
        parts.append(who)
        parts.append(g.lastUsedAt.map { String(localized: "last used \(TimeText.relative($0))", comment: "“last used 2 days ago”") }
            ?? String(localized: "not used yet"))
        return parts.joined(separator: " · ")
    }

    // MARK: Guard

    /// What Sidefolk may do, after how much it asks (the hero): the internet, folders, what is always allowed, what
    /// happens when nobody answers, and what may happen at all.
    private var guardSettings: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            InternetGroup(model: model)
            folders
            grants
            allowedNow
            UnansweredGroup(model: model)
            flowsApproved
            SettingsGroup(title: "What Sidefolk may do", footer: "Switched off, Sidefolk and connected agents can't do it at all, even if you'd say yes, in every mode.",
                          anchor: .capabilities) {
                ForEach(Self.switches, id: \.0) { capability, title, detail in
                    SettingsToggle(title: title, detail: detail, isOn: Binding(
                        get: { !model.policy.disabled.contains(capability) },
                        set: { on in
                            Task { await model.setPolicy { p in if on { p.disabled.remove(capability) } else { p.disabled.insert(capability) } } }
                        }
                    ))
                }
            }
        }
    }

    /// What flows may do without asking (D186): the one switch, and each approval with what it said, when it last ran, and Revoke.
    private var flowsApproved: some View {
        let flows = model.extensions.flatMap { ext in ext.plans.map { (extensionName: ext.name, extensionId: ext.id, plan: $0) } }
            .sorted { ($0.plan.lastUsed ?? $0.plan.approvedAt) > ($1.plan.lastUsed ?? $1.plan.approvedAt) }
        return SettingsGroup(title: "Flows you approved",
                             footer: "A flow asks on a card that says what it does, and again when its time is up or you end it, when a server's program changes, or if you ask to be asked every time. An edit that does something new asks too, except that in Auto and in Full access some additions are let through and History shows them. An update of the add-on itself does not ask again. This is the one thing on that card you can take back for every flow at once.") {
            SettingsToggle(title: "A flow may pass what it reads to servers",
                           detail: "On: a flow you approved may put what it read or wrote into the fields of a server or another add-on's tool, where its card says so: words from a page or a file, but also your own notes, reminders and calendar, what your AI wrote and what other servers answered. Off: those lines ask each time. What you type into a flow, and anything an add-on says is yours, is not held back.",
                           isOn: Binding(get: { model.policy.flowsMayPassToServers },
                                         set: { on in Task { await model.setPolicy { $0.flowsMayPassToServers = on } } }))
            Text("Here is what you approved. One that nobody has used for 60 days ends by itself, and its extension says so.", comment: "Settings › Trust: above the list of approved flows")
                .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.m)
            if flows.isEmpty {
                InlineEmpty(text: "Nothing yet. When you approve a flow, it's listed here.", systemImage: "checkmark.shield")
            }
            ForEach(flows, id: \.plan.id) { item in
                FlowApprovedRow(extensionName: item.extensionName, plan: item.plan) { Task { await model.endPlan(item.plan, extensionId: item.extensionId) } }
            }
        }
    }

    // MARK: Your data

    private var data: some View {
        SettingsGroup(title: "Your data") {
            BackupRows(model: model)
            SettingsRow(.exportData) {
                Button("Export data…") { save(name: String(localized: "Sidefolk Export"), type: .json) { await model.exportData(to: $0) } }
                    .buttonStyle(.sf(.secondary))
            }
            SettingsRow(.diagnostics) {
                Button("Export diagnostics…") {
                    save(name: String(localized: "Sidefolk Diagnostics"), type: .zip) { await model.exportDiagnostics(to: $0) }
                }
                    .buttonStyle(.sf(.secondary))
            }
            SettingsToggle(.debugLogging, isOn: Binding(get: { model.settings.debugLogging }, set: { model.setDebugLogging($0) }))
            if let message = model.dataMessage {
                Group {
                    switch message {
                    case .success(let text): Label(text, systemImage: "checkmark.circle.fill").foregroundStyle(Theme.success)
                    case .failure(let error): Label(error.description, systemImage: "exclamationmark.circle.fill").foregroundStyle(Theme.danger)
                    }
                }
                .font(Theme.Font.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Space.l)
                .padding(.vertical, Theme.Space.m)
            }
            SettingsRow(.deleteAll) {
                Button("Delete all data…") { confirmingDelete = true }.buttonStyle(.sf(.destructive))
            }
        }
    }

    private func save(name: String, type: UTType, then action: @escaping (URL) async -> Void) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(name) \(Date().formatted(.iso8601.year().month().day()))"
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        Task {
            let response: NSApplication.ModalResponse
            if let window = NSApp.keyWindow { response = await panel.beginSheetModal(for: window) } else { response = panel.runModal() }
            guard response == .OK, let url = panel.url else { return }
            await action(url)
        }
    }
}

/// Deleting everything needs the word typed out, so it can't happen by accident.
struct DeleteAllSheet: View {
    var model: SettingsModel
    @State private var typed = ""
    @State private var deleting = false
    @State private var error: UserFacingError?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(spacing: Theme.Space.m) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 22)).foregroundStyle(Theme.danger)
                    .accessibilityHidden(true)
                Text("Delete all Sidefolk data?").font(Theme.Font.heading).foregroundStyle(Theme.ink)
            }
            Text("This removes every note, reminder, watcher, folder grant and extension, your history and logs, and the keys saved in your Keychain. Sidefolk starts fresh. This can't be undone.")
                .font(Theme.Font.body).foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Type “\(Self.word)” to confirm.").font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                TextField("Confirmation", text: $typed, prompt: Text(verbatim: "")).fieldHint(Text(verbatim: Self.word), showing: typed.isEmpty)
                    .lanternField()
                    .accessibilityLabel(Text("Type “\(Self.word)” to confirm."))
            }
            if let error { InlineError(error: error) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.sfSecondary).keyboardShortcut(.cancelAction)
                Button(deleting ? "Deleting…" : "Delete Everything") {
                    deleting = true
                    Task {
                        error = await model.deleteAllData()
                        deleting = false
                        if error == nil { dismiss() }
                    }
                }
                .buttonStyle(.sfDestructive)
                .disabled(!confirmed || deleting)
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: 440)
        .background(Theme.surface)
    }

    /// The word to type, in the app's language; the English one works too.
    private static let word = String(localized: "delete", comment: "The word typed to confirm deleting everything; lower case")

    private var confirmed: Bool {
        let typed = typed.trimmingCharacters(in: .whitespaces).lowercased()
        return typed == Self.word.lowercased() || typed == "delete"
    }
}

/// One flow the person approved: its name, whose it is, when it last ran, what it said it would do, and Revoke.
private struct FlowApprovedRow: View {
    var extensionName: String
    var plan: ExtensionPlanInfo
    var revoke: () -> Void
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ext: plan.title.isEmpty ? plan.id : plan.title).font(Theme.Font.body).foregroundStyle(Theme.ink)
                    Text(verbatim: detail).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(2)
                }
                Spacer(minLength: Theme.Space.s)
                Button { revoke() } label: { Text("Revoke") }.buttonStyle(.sf(.secondary))
            }
            if !plan.card.isEmpty {
                DisclosureGroup(isExpanded: $open) {
                    Text(verbatim: plan.card).font(Theme.Font.callout).foregroundStyle(Theme.ink).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, Theme.Space.xs)
                } label: {
                    Text("What it may do", comment: "Settings › Trust: opens the words the person read when they approved a flow").font(Theme.Font.caption)
                }
            }
        }
        .padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.m)
    }

    private var detail: String {
        var parts = [extensionName]
        parts.append(plan.lastUsed.map { String(localized: "Last ran \(TimeText.relative($0))", comment: "Settings › Trust: when a flow last ran without asking; a relative date") }
                     ?? String(localized: "Hasn't run yet", comment: "Settings › Trust: a flow that was approved and hasn't run"))
        if plan.stands != .always { parts.append(String(localized: "Nobody read all of it", comment: "Settings › Trust: a flow Full access or Auto let through without showing a card for some or all of it")) }
        if plan.callsToday > 0 { parts.append(String(localized: "Today: \(plan.callsToday)", comment: "Settings › Trust: how many actions a flow made today, a count")) }
        return parts.joined(separator: " · ")
    }
}
