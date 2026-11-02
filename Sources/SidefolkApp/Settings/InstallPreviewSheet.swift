import AppKit
import SidefolkCore
import SwiftUI

/// What installing an extension would allow, before anything is installed: a two-step passport (D71, D84). First who
/// made it (where it comes from, said as loudly as that source calls for, what it is and what it adds), then what it
/// can touch (each permission with what keeps it in check, the risky combinations, what happens after). The same
/// sheet serves the gallery, a folder the person chose, a sample, and a draft Sidefolk's AI wrote for them (D39). The
/// header and the buttons never scroll; the body does, in the height the screen has room for.
struct InstallPreviewSheet: View {
    enum Step: Int { case who = 1, touch = 2 }

    var preview: ExtensionInstallPreview
    var model: SettingsModel
    /// Closes the window it is shown in (`InstallPreviewWindow`); nil when it is a sheet.
    var close: (() -> Void)? = nil
    @State var step: Step = .who
    @State private var armed = false
    @State private var installing = false
    @State private var showsAdds = false
    @State private var error: UserFacingError?
    /// How tall the body may be before it scrolls, taken once as the sheet opens.
    @State private var room = InstallPreviewSheet.roomForDetails
    /// The body at its full height, measured; until then, as much room as there is.
    @State private var bodyHeight: CGFloat = InstallPreviewSheet.roomForDetails
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header.padding([.horizontal, .top], Theme.Space.xl).padding(.bottom, Theme.Space.l)
            ScrollView {
                Group {
                    switch step {
                    case .who: who
                    case .touch: touch
                    }
                }
                .padding(.horizontal, Theme.Space.xl)
                .padding(.bottom, Theme.Space.l)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bodyHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(bodyHeight, room))
            Rectangle().fill(Theme.line).frame(height: 1)
            footer
        }
        .frame(width: Theme.Size.installSheet)
        .background(Theme.surface)
        .task(id: step) {
            // Like approval cards: Install is inert for a moment after it appears, so a stray Return can't install it.
            armed = false
            guard step == .touch else { return }
            try? await Task.sleep(for: .milliseconds(800))
            armed = true
        }
        #if DEBUG
        // `installSheet:continue | install` from scripts/dev.swift: Continue, then Install or Update, as clicks would
        // (Install only once armed).
        .onReceive(NotificationCenter.default.publisher(for: Self.devPress)) { note in
            switch (note.object as? String, step) {
            case ("continue", .who): go(.touch)
            case ("install", .touch) where armed && !installing:
                installing = true
                Task {
                    error = await model.install(preview)
                    installing = false
                    if error == nil { finish() }
                }
            default: break
            }
        }
        #endif
    }

    #if DEBUG
    static let devPress = Notification.Name("sidefolk.dev.installSheet")
    #endif

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            // The extension's own icon, with Guard on duty: this is a permission question.
            ExtensionBadge(look: preview.look, size: 56)
                .overlay(alignment: .bottomTrailing) { FolkBadge(name: "guard", size: 22).offset(x: 6, y: 6) }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: Theme.Space.m) {
                    titles
                    Spacer(minLength: Theme.Space.s)
                    StepIndicator(step: step)
                }
                // Longer languages: the steps go under the title rather than squeezing it.
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    titles
                    StepIndicator(step: step)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 2) {
            Group {
                switch step {
                case .who: preview.isUpdate ? Text("Update \(preview.name)?") : Text("Install \(preview.name)?")
                case .touch: Text("What \(preview.name) can touch", comment: "Install sheet, step 2: its title")
                }
            }
            .font(Theme.Font.title1).foregroundStyle(Theme.ink)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            origin.font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(1).truncationMode(.middle)
        }
    }

    // MARK: Step 1, who made it

    private var who: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            // Where it comes from first: that's what tells how much to read into the rest (D71).
            InstallSourceRow(source: review.source)
            if !preview.description.isEmpty {
                Text(preview.description).font(Theme.Font.body).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            }
            if let update = review.update { InstallUpdateBox(update: update, tone: review.tone) }
            facts
            if !adds.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text("It adds", comment: "Install sheet: what the extension adds to Sidefolk").font(Theme.Font.headline).foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                    FlowRow(spacing: Theme.Space.s) {
                        ForEach(adds, id: \.text) { chip in Chip(verbatim: chip.text, tone: .neutral, systemImage: chip.symbol) }
                    }
                }
            }
        }
    }

    private var facts: some View {
        HStack(spacing: 0) {
            fact(Text("Version", comment: "Install sheet: a fact"), Text(verbatim: preview.version))
            Rectangle().fill(Theme.line).frame(width: 1)
            fact(Text("From", comment: "Install sheet: a fact, where it comes from"), sourceWord)
            Rectangle().fill(Theme.line).frame(width: 1)
            fact(Text("Asks for", comment: "Install sheet: a fact, how many permissions"),
                 review.lines.isEmpty ? Text("Nothing", comment: "Install sheet: it asks for no permission")
                     : Text("\(review.lines.count) permissions", comment: "Install sheet: “3 permissions”"))
        }
        .fixedSize(horizontal: false, vertical: true)
        .cardSurface()
    }

    private func fact(_ label: Text, _ value: Text) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            label.font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
            value.font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink).lineLimit(2)
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var sourceWord: Text {
        switch review.source {
        case .gallery: Text("The Sidefolk gallery", comment: "Install sheet: where it comes from, as a fact")
        case .draft: Text("Written for you", comment: "Install sheet: where it comes from, as a fact")
        case .folder: Text("A folder on this Mac", comment: "Install sheet: where it comes from, as a fact")
        }
    }

    /// What it adds, as chips: pages in Home, tools, watches, sentences it answers without AI.
    private var adds: [(symbol: String, text: String)] {
        var chips: [(symbol: String, text: String)] = []
        if !preview.pageNames.isEmpty {
            chips.append(("rectangle.stack", String(localized: "\(preview.pageNames.count) pages in Home", comment: "Install sheet: what it adds, “2 pages in Home”")))
        }
        if !preview.toolNames.isEmpty {
            chips.append(("sparkles", String(localized: "\(preview.toolNames.count) things \(model.settings.companionName) can do",
                                             comment: "Install sheet: what it adds, its tools, “4 things Mochi can do”")))
        }
        if !preview.watcherNames.isEmpty {
            chips.append(("binoculars", String(localized: "\(preview.watcherNames.count) kinds of watch", comment: "Install sheet: what it adds")))
        }
        if !preview.commands.isEmpty {
            chips.append(("text.bubble", String(localized: "\(preview.commands.count) sentences it answers without AI", comment: "Install sheet: what it adds")))
        }
        return chips
    }

    // MARK: Step 2, what it can touch

    private var touch: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            Text("It runs in a sandbox that allows only these. Each one says what keeps it in check.", comment: "Install sheet, step 2")
                .font(Theme.Font.body).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
            if let update = review.update, update.widens { InstallUpdateBox(update: update, tone: review.tone) }
            // A warning comes before what it warns about; a calm note can follow the list it sums up.
            if !review.cautions.isEmpty, review.tone == .careful { InstallCautionBox(cautions: review.cautions, tone: .careful) }
            if review.lines.isEmpty {
                Text("Nothing beyond its own data folder.").font(Theme.Font.body).foregroundStyle(Theme.inkMuted)
            } else {
                RowsCard {
                    ForEach(review.lines, id: \.self) { InstallPermissionRow(line: $0) }
                }
            }
            if !review.cautions.isEmpty, review.tone == .goodToKnow { InstallCautionBox(cautions: review.cautions, tone: .goodToKnow) }
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("After you install").font(Theme.Font.headline).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
                ForEach(review.next, id: \.self) { line in
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.success).accessibilityHidden(true)
                        Text(verbatim: line).font(Theme.Font.body).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if !preview.toolNames.isEmpty || !preview.watcherNames.isEmpty || !preview.pageNames.isEmpty || !preview.commands.isEmpty {
                // Every name it adds is long for a big extension and isn't a permission: folded, one click away.
                DisclosureGroup(isExpanded: $showsAdds) {
                    addedNames.padding(.top, 4)
                } label: {
                    Text("Everything it adds, by name", comment: "Install sheet: folded list of tools, watches, pages")
                        .font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                }
            }
        }
    }

    private var addedNames: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !preview.toolNames.isEmpty {
                Text(ExtensionWords.tools(preview.toolNames)).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
            }
            if !preview.watcherNames.isEmpty {
                Text(ExtensionWords.watchers(preview.watcherNames)).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
            }
            if !preview.pageNames.isEmpty {
                Text(ExtensionWords.pages(preview.pageNames, background: preview.pagesInBackground))
                    .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
            }
            if !preview.commands.isEmpty {
                Text(ExtensionWords.commands(preview.commands)).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(preview.additions, id: \.self) { line in
                Text(ext: line).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Footer

    /// What went wrong, if anything, and the choice: always in sight, whatever the sheet holds.
    private var footer: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if let error { InlineError(error: error) }
            HStack(spacing: Theme.Space.s) {
                switch step {
                case .who:
                    Button("Show files") { NSWorkspace.shared.activateFileViewerSelecting([preview.sourceFolder]) }
                        .buttonStyle(.sf(.plain))
                case .touch:
                    Button { go(.who) } label: {
                        Label { Text("Back") } icon: { Image(systemName: "chevron.backward").flipsForRightToLeftLayoutDirection(true) }
                    }
                    .buttonStyle(.sf(.secondary, size: .large))
                }
                Spacer()
                Button("Cancel", action: finish).buttonStyle(.sf(.secondary, size: .large)).keyboardShortcut(.cancelAction)
                switch step {
                case .who:
                    Button { go(.touch) } label: {
                        HStack(spacing: 4) {
                            Text("Continue", comment: "Install sheet: from who made it to what it can touch")
                            Image(systemName: "chevron.forward").font(.system(size: 10, weight: .bold)).flipsForRightToLeftLayoutDirection(true)
                        }
                    }
                    .buttonStyle(.sf(.primary, size: .large))
                    .keyboardShortcut(.defaultAction)
                case .touch:
                    Button(installing ? "Installing…" : preview.isUpdate ? "Update \(preview.name)" : "Install \(preview.name)") {
                        installing = true
                        Task {
                            error = await model.install(preview)
                            installing = false
                            if error == nil { finish() }
                        }
                    }
                    .buttonStyle(.sf(.primary, size: .large))
                    .disabled(!armed || installing)
                }
            }
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.vertical, Theme.Space.l)
    }

    private func go(_ next: Step) {
        withAnimation(reduceMotion ? nil : Theme.Motion.standard) { step = next }
    }

    /// The body's height before it scrolls. A sheet hangs from just under its window's top, so its room is from
    /// there down to the Dock, less the header, the buttons and a margin; a window of its own gets the screen's height.
    private static var roomForDetails: CGFloat {
        let screen = (NSApp.keyWindow?.screen ?? NSScreen.main)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
        let top = NSApp.keyWindow.map { min($0.frame.maxY, screen.maxY) - 40 } ?? screen.maxY
        return max(260, top - screen.minY - 240)
    }

    private var review: InstallReview { preview.review }

    private func finish() {
        if let close { close() } else { dismiss() }
    }

    private var origin: Text {
        // A gallery download sits in a temporary folder whose path means nothing; a folder's path says which one.
        guard review.source == .folder else { return Text("Version \(preview.version)") }
        return Text("Version \(preview.version) · from \(FolderAccess.displayPath(preview.sourceFolder.path))")
    }
}

/// "① Who made it ── ② What it can touch": where the passport is.
private struct StepIndicator: View {
    var step: InstallPreviewSheet.Step

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            item(1, Text("Who made it", comment: "Install sheet: step 1"), done: step == .touch, current: step == .who)
            Rectangle().fill(Theme.line).frame(width: 20, height: 1)
            item(2, Text("What it can touch", comment: "Install sheet: step 2"), done: false, current: step == .touch)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Step \(step.rawValue) of 2", comment: "Install sheet: which step, read by VoiceOver"))
    }

    private func item(_ number: Int, _ title: Text, done: Bool, current: Bool) -> some View {
        HStack(spacing: 6) {
            ZStack {
                Circle().fill(current ? Theme.accent : done ? Theme.successSoft : Theme.well)
                if done {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.success)
                } else {
                    Text(verbatim: number.formatted()).font(.system(size: 11, weight: .bold)).foregroundStyle(current ? Theme.onAccent : Theme.inkMuted)
                }
            }
            .frame(width: 20, height: 20)
            title.font(current ? Theme.Font.captionStrong : Theme.Font.caption).foregroundStyle(current ? Theme.ink : Theme.inkMuted)
        }
    }
}
