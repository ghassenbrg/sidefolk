import AppKit
import SidefolkCore
import SwiftUI
import UniformTypeIdentifiers

/// Settings › Privacy & Permissions: what is stored, which folders Sidefolk may use, what is
/// always allowed, how cautious Guard is, and the user's data (export, delete).
struct PrivacySettingsView: View {
    var model: SettingsModel
    @State private var confirmingDelete = false

    /// The capabilities a person can switch off, in the words the Settings page uses.
    private static let switches: [(Capability, LocalizedStringKey, LocalizedStringKey)] = [
        (.shell, "Running commands", "Shell commands, always shown word for word before they run."),
        (.network, "Internet access", "Fetching pages and checking sites."),
        (.clipboard, "Clipboard", "Reading and writing what you copied."),
        (.filesWrite, "Changing files", "Moving, renaming and creating files in your folders."),
        (.apps, "Opening apps and links", "Launching apps and opening web pages."),
    ]

    var body: some View {
        SettingsPage {
            keeps
            SettingsGroup(title: "History", footer: "Recent requests let you follow up (“and tomorrow too”). They're never shown as a chat log.") {
                SettingsRow(title: "Keep recent requests for") {
                    Picker("Keep recent requests for", selection: Binding(
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
            }
            folders
            grants
            guardSettings
            data
        }
        .sheet(isPresented: $confirmingDelete) { DeleteAllSheet(model: model) }
    }

    // MARK: What Sidefolk keeps

    private var keeps: some View {
        SettingsGroup(title: "What Sidefolk keeps", footer: "Everything stays on this Mac. It's encrypted at rest by FileVault when FileVault is on.") {
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
                      footer: "Sidefolk only touches files inside these folders. Anything it deletes goes to the Trash.") {
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
                Button("Add Folder…", action: addFolder).buttonStyle(.sf(.secondary))
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
        SettingsGroup(title: "Always allowed", footer: "Revoke any of these and Sidefolk asks again next time.") {
            if model.grants.isEmpty {
                InlineEmpty(text: "Nothing yet. When you choose “Always allow”, it's listed here.", systemImage: "checkmark.shield")
            }
            ForEach(model.grants) { grant in
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

    private var guardSettings: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            SettingsGroup(title: "Guard") {
                ChoiceRow(title: "Standard", detail: "Asks once for each kind of action and remembers “Always allow”.",
                          selected: model.policy.mode == .askOncePerKind) {
                    Task { await model.setPolicy { $0.mode = .askOncePerKind } }
                }
                ChoiceRow(title: "Cautious", detail: "Asks every time something would change outside Sidefolk, even if you allowed it before.",
                          selected: model.policy.mode == .askEveryTime) {
                    Task { await model.setPolicy { $0.mode = .askEveryTime } }
                }
            }
            SettingsGroup(title: "What Sidefolk may do", footer: "Switched off, Sidefolk and connected agents can't do it at all, even if you'd say yes.") {
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

    // MARK: Your data

    private var data: some View {
        SettingsGroup(title: "Your data") {
            SettingsRow(title: "Export data", detail: "Notes, reminders, watches and settings as one JSON file. No keys.") {
                Button("Export Data…") { save(name: String(localized: "Sidefolk Export"), type: .json) { await model.exportData(to: $0) } }
                    .buttonStyle(.sf(.secondary))
            }
            SettingsRow(title: "Diagnostics", detail: "Logs and versions for a bug report, without your notes or messages.") {
                Button("Export Diagnostics…") {
                    save(name: String(localized: "Sidefolk Diagnostics"), type: .zip) { await model.exportDiagnostics(to: $0) }
                }
                    .buttonStyle(.sf(.secondary))
            }
            SettingsToggle(title: "Debug logging", detail: "More detail in the local log. Turn it off when you're done.",
                           isOn: Binding(get: { model.settings.debugLogging }, set: { model.setDebugLogging($0) }))
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
            SettingsRow(title: "Delete all Sidefolk data", detail: "Notes, reminders, watches, history, logs and saved keys. This can't be undone.") {
                Button("Delete All Data…") { confirmingDelete = true }.buttonStyle(.sf(.destructive))
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
                TextField("Confirmation", text: $typed, prompt: Text(verbatim: Self.word))
                    .textFieldStyle(.roundedBorder)
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
