import SidefolkCharacter
import SidefolkCore
import SwiftUI

/// Settings › Companion's chooser (D30): the chosen companion live, with its name, colour and what
/// it wears and a few states to try, above a gallery of every companion on offer. Changes apply
/// to the desktop at once.
struct CompanionPicker: View {
    var model: SettingsModel
    @State private var trying = Trial.idle

    private var settings: AppSettings { model.settings }
    private var chosen: CompanionChoice { CompanionArt.offered.contains(settings.companion) ? settings.companion : .mochi }
    /// A companion from "Made by you" in use: the stage and the title show it, and no built-in card is picked.
    private var custom: CustomCompanion? { CompanionArt.custom(settings.customCompanion) }
    private var style: CompanionStyle { settings.style(for: chosen) }
    /// Shown in 3D (D51): its 3D character is fixed as designed, so colour and what it wears are
    /// for the 2D rig only.
    private var threeD: Bool { custom == nil && CompanionArt.threeD(chosen, in: settings) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Eyebrow(text: "Companion").padding(.leading, Theme.Space.xs)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: Theme.Space.l) {
                    stage
                    details
                }
                .padding(Theme.Space.l)
                Rectangle().fill(Theme.line).frame(height: 1)
                gallery.padding(Theme.Space.m)
            }
            .cardSurface()
        }
    }

    // MARK: The chosen one

    private var stage: some View {
        VStack(spacing: Theme.Space.s) {
            CompanionStage(look: CompanionArt.look(for: settings), name: settings.companionName, state: trying.state)
                .frame(width: 176, height: 176)
                .background(Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .accessibilityLabel("\(settings.companionName), as it looks on your desktop")
            Group {
                if Self.trialSegmentsFit {
                    trial.pickerStyle(.segmented).frame(width: 236)
                } else {
                    trial.pickerStyle(.menu).fixedSize()
                }
            }
            .accessibilityLabel("Try a state")
        }
    }

    /// Segments under the stage while the four names fit: AppKit squeezes them a little (English
    /// needs 272 points at rest, shown in 236), and a longer language gets a menu instead of cut words.
    /// The language is fixed for the launch, so it is measured once.
    private static let trialSegmentsFit: Bool = {
        let control = NSSegmentedControl(labels: Trial.allCases.map { String(localized: $0.title) }, trackingMode: .selectOne,
                                         target: nil, action: nil)
        control.segmentDistribution = .fit
        return control.fittingSize.width <= 280
    }()

    private var trial: some View {
        Picker("Try", selection: $trying) {
            ForEach(Trial.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .labelsHidden()
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: custom?.name ?? chosen.defaultName).font(Theme.Font.title).foregroundStyle(Theme.ink)
                Text(verbatim: custom.map { $0.summary ?? "" } ?? CompanionArt.role(chosen)).font(Theme.Font.body).foregroundStyle(Theme.inkMuted)
            }
            labelled("Name") {
                CommitField(label: "Companion name", prompt: Text(verbatim: chosen.defaultName), value: settings.companionName, width: 200) { name in
                    let clean = name.isEmpty ? chosen.defaultName : String(name.prefix(30))
                    model.update { $0.companionName = clean }
                }
            }
            if custom == nil, chosen.dimensions.count > 1, Companion3DStage.folder != nil {
                labelled("Look") {
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("Look", selection: Binding(get: { settings.dimension(for: chosen) }, set: { next in
                            let choice = chosen
                            model.update { $0.setDimension(next, for: choice) }
                        })) {
                            Text(verbatim: "3D").tag(CompanionDimension.threeD)
                            Text(verbatim: "2D").tag(CompanionDimension.twoD)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                        Text(threeD ? "Livelier, and uses a little more of your Mac." : "Lightest on your Mac, with a color and a scarf to choose.")
                            .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if !threeD { wardrobe }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Colour and what it wears, for a companion drawn in 2D.
    @ViewBuilder private var wardrobe: some View {
        labelled("Wears") {
            Picker("Wears", selection: Binding(get: { style.accessory }, set: { wear in restyle { $0.accessory = wear } })) {
                ForEach(CompanionAccessory.allCases, id: \.self) { Text(Self.title($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        labelled("Color") {
            VStack(alignment: .leading, spacing: 4) {
                AccentSwatches(selected: style.color) { color in restyle { $0.color = color } }
                    .disabled(!colours)
                    .opacity(colours ? 1 : 0.4)
                Text(colourDetail).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func labelled(_ title: LocalizedStringKey, @ViewBuilder _ control: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(Theme.Font.captionStrong).foregroundStyle(Theme.inkMuted)
            control()
        }
    }

    /// Whether the colour paints anything: the companion's own accents, or what it wears.
    private var colours: Bool {
        CompanionArt.species(chosen).hasOwnAccents || style.accessory != .none
    }

    private var colourDetail: LocalizedStringKey {
        switch chosen {
        case .sidefolk: "Its eyes, ear lights and what it wears."
        case .spark: "Its headphones, antenna, eyes and what it wears."
        default: colours ? "What it wears." : "Give it something to wear to choose a color."
        }
    }

    private func restyle(_ change: @escaping @Sendable (inout CompanionStyle) -> Void) {
        let choice = chosen
        model.update { s in
            var next = s.style(for: choice)
            change(&next)
            s.setStyle(next, for: choice)
        }
    }

    // MARK: Everyone

    private var gallery: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: Theme.Space.s)], spacing: Theme.Space.s) {
            ForEach(CompanionArt.offered, id: \.self) { choice in
                CompanionCard(choice: choice,
                              image: CompanionArt.preview(choice, style: settings.style(for: choice),
                                                          threeD: CompanionArt.threeD(choice, in: settings), side: 84),
                              selected: custom == nil && choice == chosen) {
                    model.update { $0.choose(choice) }
                }
            }
        }
    }

    static func title(_ accessory: CompanionAccessory) -> LocalizedStringKey {
        switch accessory {
        case .none: "Nothing"
        case .scarf: "Scarf"
        }
    }

    /// The states to try in the preview.
    enum Trial: CaseIterable {
        case idle, thinking, working, sleeping

        var title: LocalizedStringResource {
            switch self {
            case .idle: "Idle"
            case .thinking: "Thinking"
            case .working: "Working"
            case .sleeping: "Sleeping"
            }
        }

        var state: CharacterState {
            switch self {
            case .idle: .idle
            case .thinking: .thinking
            case .working: .working(.laptop)
            case .sleeping: .sleeping
            }
        }
    }
}

/// The chosen companion, alive: the same view the desktop uses, in the state being tried, and its
/// 3D character over it when it is shown in 3D.
private struct CompanionStage: NSViewRepresentable {
    var look: CharacterLook
    var name: String
    var state: CharacterState

    func makeNSView(context: Context) -> LiveCompanion {
        let view = LiveCompanion(frame: NSRect(x: 0, y: 0, width: 176, height: 176))
        update(view)
        return view
    }

    func updateNSView(_ view: LiveCompanion, context: Context) { update(view) }

    private func update(_ view: LiveCompanion) {
        view.character.look = look
        view.character.displayName = name
        view.character.state = state
        view.show3D(look.custom == nil && look.threeD ? look.species : nil)
    }

    final class LiveCompanion: NSView {
        let character: CharacterView
        private var stage: Companion3DStage?
        private var occlusion: NSObjectProtocol?

        override init(frame: NSRect) {
            character = CharacterView(frame: NSRect(origin: .zero, size: frame.size))
            character.autoresizingMask = [.width, .height]
            super.init(frame: frame)
            addSubview(character)
        }

        @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

        // WebGL keeps drawing in a closed or covered Settings window unless told to stop.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            occlusion.map(NotificationCenter.default.removeObserver)
            occlusion = nil
            guard let window else { stage?.setVisible(false); return }
            occlusion = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                                               object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.syncVisible() }
            }
            syncVisible()
        }

        private func syncVisible() {
            stage?.setVisible(window?.occlusionState.contains(.visible) ?? false)
        }

        /// The chosen form at once, as on the desktop (`CompanionWindowController.show3D`).
        func show3D(_ species: CharacterSpecies?) {
            guard let species else { removeStage(); return }
            character.drawsRig = false
            if let stage { stage.show(species); return }
            guard let next = Companion3DStage(species) else { character.drawsRig = true; return }
            next.frame = bounds
            next.autoresizingMask = [.width, .height]
            addSubview(next, positioned: .below, relativeTo: character)
            stage = next
            next.onReady = { [weak self, weak next] in
                guard let self, let next else { return }
                next.handle(.liveliness(self.character.motionLevel))
                next.handle(.state(self.character.state))
                self.syncVisible()
            }
            next.onFailed = { [weak self] in self?.removeStage() }
            character.onCue = { [weak next] in next?.handle($0) }
        }

        private func removeStage() {
            stage?.removeFromSuperview()
            stage = nil
            character.onCue = nil
            character.drawsRig = true
        }
    }
}

/// One companion in the gallery: as it looks at rest, its name and what it does.
private struct CompanionCard: View {
    var choice: CompanionChoice
    var image: NSImage
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(nsImage: image).resizable().scaledToFit().frame(width: 84, height: 84)
                Text(choice.defaultName).font(selected ? Theme.Font.bodyStrong : Theme.Font.body).foregroundStyle(Theme.ink)
                Text(CompanionArt.role(choice)).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                    .multilineTextAlignment(.center).lineLimit(2, reservesSpace: true).minimumScaleFactor(0.85)
            }
            .padding(.horizontal, Theme.Space.xs)
            .padding(.vertical, Theme.Space.s)
            .frame(maxWidth: .infinity)
            .background(selected ? Theme.accentSoft : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(selected ? Theme.accent : Theme.line, lineWidth: selected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(choice.defaultName), \(CompanionArt.role(choice))")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The brand colours a companion's accents can take.
private struct AccentSwatches: View {
    var selected: CompanionAccent
    var choose: (CompanionAccent) -> Void

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            ForEach(CompanionAccent.allCases, id: \.self) { accent in
                Button { choose(accent) } label: {
                    ZStack {
                        Circle().fill(color(accent))
                        if accent == selected {
                            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.navy)
                        }
                    }
                    .frame(width: 22, height: 22)
                    .padding(3)
                    .overlay(Circle().strokeBorder(accent == selected ? color(accent) : .clear, lineWidth: 2))
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(name(accent))
                .accessibilityLabel(name(accent))
                .accessibilityAddTraits(accent == selected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    private func color(_ accent: CompanionAccent) -> Color {
        switch accent {
        case .aqua: Theme.aqua
        case .coral: Theme.coral
        case .mint: Theme.mint
        case .lightBlue: Theme.lightBlue
        }
    }

    private func name(_ accent: CompanionAccent) -> LocalizedStringKey {
        switch accent {
        case .aqua: "Aqua"
        case .coral: "Coral"
        case .mint: "Mint"
        case .lightBlue: "Light blue"
        }
    }
}
