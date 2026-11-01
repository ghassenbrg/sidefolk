import AppKit
import SidefolkCore
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// A Sidefolk backup: a zip under its own name (D91).
    static let sidefolkBackup = UTType(filenameExtension: BackupManifest.fileExtension, conformingTo: .zip) ?? .zip
}

extension SettingsModel {
    /// Picks a backup file, opens and checks it, then shows what it holds in the restore sheet.
    func chooseBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.sidefolkBackup]
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "Choose a Sidefolk backup to restore.")
        Task {
            let response: NSApplication.ModalResponse
            if let window = NSApp.keyWindow { response = await panel.beginSheetModal(for: window) } else { response = panel.runModal() }
            guard response == .OK, let url = panel.url else { return }
            await open(backup: url)
        }
    }

    func open(backup url: URL) async {
        backupMessage = nil
        switch await services.openBackup(url) {
        case .success(let backup): restoreCandidate = RestoreCandidate(backup: backup, file: url)
        case .failure(let error): backupMessage = .failure(error)
        }
    }

    /// Asks where, then writes the backup; the sheet stays until it's written.
    func backUp(password: String?) async -> Bool {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = String(localized: "Sidefolk Backup \(Date().formatted(.iso8601.year().month().day()))",
                                            comment: "A backup's file name: “Sidefolk Backup 2026-11-01”")
        panel.allowedContentTypes = [.sidefolkBackup]
        panel.canCreateDirectories = true
        let response: NSApplication.ModalResponse
        if let window = NSApp.keyWindow { response = await panel.beginSheetModal(for: window) } else { response = panel.runModal() }
        guard response == .OK, let url = panel.url else { return false }
        if let error = await services.backUp(to: url, password: password) {
            backupMessage = .failure(error)
        } else {
            backupMessage = .success(String(localized: "Backed up to \(FolderAccess.displayPath(url.path)).", comment: "Settings › Trust › Your data"))
        }
        return true
    }
}

/// Your data's rows for a backup (D91): Back up everything, Restore from a backup, and after a restore its add-ons
/// coming back, what waits for a look, and Undo restore.
struct BackupRows: View {
    var model: SettingsModel
    private var restore: RestoreModel { model.services.restore }

    var body: some View {
        SettingsRow(.backUp) {
            Button("Back up…") { model.backingUp = true }.buttonStyle(.sf(.secondary))
        }
        SettingsRow(.restore) {
            Button("Restore…") { model.chooseBackup() }.buttonStyle(.sf(.secondary))
        }
        if let message = model.backupMessage {
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
        if restore.running {
            SettingsRow(title: Text("Installing your add-ons again…", comment: "After a restore (D91)"),
                        detail: Text("\(restore.done) of \(restore.total)", comment: "After a restore: “2 of 5” add-ons")) {
                ProgressView(value: Double(restore.done), total: Double(max(restore.total, 1))).frame(width: 120)
            }
        } else if let report = restore.report, !report.failed.isEmpty {
            ForEach(report.failed) { failure in
                SettingsRow(title: Text("\(failure.name) isn't back", comment: "After a restore: an add-on that couldn't be installed again"),
                            detail: Text(verbatim: failure.reason)) { EmptyView() }
            }
        }
        ForEach(restore.review) { item in
            SettingsRow(title: Text("\(item.name), from your backup", comment: "After a restore: an extension or companion from a folder"),
                        detail: item.kind == .extension
                            ? Text("An extension from a folder: it's installed again only once you've looked at what it can do.")
                            : Text("A companion from a folder: its character file runs as code, so it asks first.")) {
                Button("Review…") { model.services.reviewRestored(item) }.buttonStyle(.sf(.secondary))
            }
        }
        if let plan = restore.undoable, let until = restore.undoUntil {
            SettingsRow(title: Text("Restored from the backup made on \(AppCoordinator.when(plan.backupCreated))",
                                    comment: "Settings › Trust › Your data: “Restored from the backup made on 1 Nov 2026 at 10:42”"),
                        detail: Text("Undo puts back your data from before the restore, until \(until.formatted(date: .abbreviated, time: .omitted)).",
                                     comment: "Settings › Trust › Your data: “…until 8 Nov 2026.”")) {
                Button("Undo restore…") { confirmUndo() }.buttonStyle(.sf(.secondary))
            }
        }
    }

    private func confirmUndo() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Undo the restore?")
        alert.informativeText = String(localized: "Your data from before the restore comes back, and what you did since the restore is set aside. Sidefolk restarts.")
        alert.addButton(withTitle: String(localized: "Undo Restore"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if let error = model.services.undoRestore() { model.backupMessage = .failure(error) }
    }
}

/// Back up everything (D91): one file, and the keys only with a password.
struct BackupSheet: View {
    var model: SettingsModel
    @State var keys = false
    @State private var password = ""
    @State private var again = ""
    @State private var working = false
    @Environment(\.dismiss) private var dismiss

    private var passwordProblem: Text? {
        guard keys else { return nil }
        if password.count < 8 { return Text("At least 8 characters.", comment: "A backup's password") }
        if password != again { return Text("The two passwords aren't the same.") }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            Text("Back up everything").font(Theme.Font.heading).foregroundStyle(Theme.ink)
            Text("One file with your notes, reminders, watches and their history, conversations, settings, your skills and what your extensions keep. Open it on another Mac, or after starting fresh, with Restore from a backup.")
                .font(Theme.Font.body).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                BackupPoint(symbol: "shippingbox", text: Text("Add-ons from the gallery are named, then installed again from it on the other Mac."))
                BackupPoint(symbol: "folder", text: Text("Extensions and companions from a folder come along, and wait for your look before they're back."))
                BackupPoint(symbol: "terminal", text: Text("Claude Code and Codex aren't part of it: connect them again on the other Mac."))
            }
            Toggle(isOn: $keys) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Include my keys, protected by a password").font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                    Text("Your AI providers' keys and your tool servers' secrets, sealed with it. Without the password nobody can read them, Sidefolk included: it doesn't keep it.")
                        .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch).tint(Theme.accent)
            if keys {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SecureField(String(localized: "Password"), text: $password).lanternField()
                    SecureField(String(localized: "The same password again"), text: $again).lanternField()
                    if let passwordProblem, !password.isEmpty { passwordProblem.font(Theme.Font.caption).foregroundStyle(Theme.inkMuted) }
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.sfSecondary).keyboardShortcut(.cancelAction)
                Button("Back Up…") {
                    working = true
                    Task {
                        let written = await model.backUp(password: keys ? password : nil)
                        working = false
                        if written { dismiss() }
                    }
                }
                .buttonStyle(.sf(.primary, size: .regular, working: working))
                .disabled(working || passwordProblem != nil)
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: Theme.Size.sheet)
    }
}

/// What a backup holds and what restoring it does, before anything changes (D91).
struct RestoreSheet: View {
    var model: SettingsModel
    var candidate: RestoreCandidate
    @State private var password = ""
    @State private var working = false
    @State private var error: UserFacingError?
    @Environment(\.dismiss) private var dismiss

    private var manifest: BackupManifest { candidate.backup.manifest }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            Text("Restore from this backup?").font(Theme.Font.heading).foregroundStyle(Theme.ink)
            VStack(alignment: .leading, spacing: 2) {
                Text("Made on \(AppCoordinator.when(manifest.created))", comment: "The restore sheet: “Made on 1 Nov 2026 at 10:42”")
                    .font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                Text(verbatim: [manifest.device, String(localized: "Sidefolk \(manifest.app)", comment: "The restore sheet: “Sidefolk 0.1.0 snapshot 673”")]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                Text(verbatim: Self.counts(manifest)).font(Theme.Font.body).foregroundStyle(Theme.ink).padding(.top, Theme.Space.xs)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.well, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                BackupPoint(symbol: "arrow.triangle.2.circlepath",
                            text: Text("It replaces your notes, reminders, watches, history and settings. What's here now is kept aside for 7 days: Undo restore puts it back."))
                BackupPoint(symbol: "shippingbox", text: Text("Add-ons from the gallery are installed again from it. Those from a folder wait for your look."))
                BackupPoint(symbol: "server.rack", text: Text("Tool servers come back switched off: they run with your permissions."))
                BackupPoint(symbol: "hand.raised", text: Text("Restore only a backup you made yourself."))
            }
            if candidate.backup.hasKeys {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text("It holds your keys, sealed with a password. Type it to bring them back, or leave it empty to restore without them.")
                        .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
                    SecureField(String(localized: "Password for the keys"), text: $password).lanternField()
                }
            }
            if let error { InlineError(error: error) }
            HStack {
                Spacer()
                Button("Cancel") {
                    candidate.backup.discard()
                    dismiss()
                }
                .buttonStyle(.sfSecondary).keyboardShortcut(.cancelAction)
                Button("Replace My Data and Restart") {
                    working = true
                    error = nil
                    Task {
                        error = await model.services.restore(candidate.backup, password: password.isEmpty ? nil : password)
                        working = false
                    }
                }
                .buttonStyle(.sf(.primary, size: .regular, working: working))
                .disabled(working)
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: Theme.Size.sheet)
    }

    /// "1,240 notes · 32 reminders · 6 watches · 4 add-ons · 2 skills", only what it has.
    static func counts(_ m: BackupManifest) -> String {
        let c = m.counts
        let parts: [String?] = [
            c.notes > 0 ? String(localized: "\(c.notes) notes", comment: "What a backup holds") : nil,
            c.reminders > 0 ? String(localized: "\(c.reminders) reminders", comment: "What a backup holds") : nil,
            c.watchers > 0 ? String(localized: "\(c.watchers) watches", comment: "What a backup holds") : nil,
            c.conversations > 0 ? String(localized: "\(c.conversations) conversations", comment: "What a backup holds") : nil,
            c.addons + c.extensions > 0 ? String(localized: "\(c.addons + c.extensions) add-ons", comment: "What a backup holds") : nil,
            c.skills > 0 ? String(localized: "\(c.skills) skills", comment: "What a backup holds") : nil,
        ]
        let shown = parts.compactMap { $0 }
        return shown.isEmpty ? String(localized: "Settings only", comment: "A backup with no notes, reminders or add-ons") : shown.joined(separator: " · ")
    }
}

/// One line of what a backup does, with its symbol.
struct BackupPoint: View {
    var symbol: String
    var text: Text

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Image(systemName: symbol).foregroundStyle(Theme.inkMuted).frame(width: 18).accessibilityHidden(true)
            text.font(Theme.Font.body).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
        }
    }
}
