import SidefolkCore
import SwiftUI

// What leads an extension's page and how its actions look (D73): a hero that says what is happening now with its main
// actions, large; a transport for something playing; and every button drawn by its emphasis, so the one primary
// action is found at a glance and the rarely needed ones stay quiet. All of it is Sidefolk's drawing in the theme's
// colours; every word is the extension's, and every click runs one of its own tools as the person, through Guard.

/// One of the extension's buttons: primary filled in the accent colour, secondary framed, destructive red, plain as
/// accent text. A destructive button is filled when it is the page's main action (nothing on the page is primary):
/// "Stop sharing" while sharing. It shows that it is working until the tool answers.
struct PageButton: View {
    var control: ExtensionPage.Control
    var model: ExtensionPageModel
    var large = false
    var leads = false
    @State private var running = false

    var body: some View {
        Button {
            running = true
            Task {
                await model.run(control, on: nil)
                running = false
            }
        } label: {
            HStack(spacing: 6) {
                if running {
                    ProgressView().controlSize(.small).scaleEffect(large ? 0.8 : 0.6).frame(width: 14, height: 14)
                } else if let symbol = control.symbol {
                    Image(systemName: symbol)
                }
                Text(verbatim: control.label)
            }
        }
        .buttonStyle(.sf(kind, compact: !large && control.style != .primary, large: large))
        .disabled(running || control.disabled)
        .help(control.detail.map { Text(verbatim: $0) } ?? Text(verbatim: control.label))
    }

    private var kind: SFButtonStyle.Kind {
        switch control.style ?? .secondary {
        case .primary: .primary
        case .secondary: .secondary
        case .destructive: leads ? .danger : .destructive
        case .plain: .quiet
        }
    }
}

extension ExtensionPage {
    /// Whether any button on the page is primary: when none is, a destructive one in the hero leads (D73).
    var hasPrimary: Bool {
        if hero == nil, summary?.control?.style == .primary { return true }
        return sections.contains { s in
            s.blocks.contains { b in
                switch b {
                case .control(let c): c.style == .primary
                case .hero(let h): h.actions.contains { $0.style == .primary }
                case .transport(let t): t.buttons.contains { $0.style == .primary }
                default: false
                }
            }
        }
    }
}

// MARK: Hero

/// What the page is about right now: a state on top, a large title, a line, maybe a code to compare or live numbers,
/// a picture of what it is about, and the main actions, large. It replaces the summary banner when it leads the page.
struct HeroView: View {
    var hero: ExtensionPage.Hero
    var model: ExtensionPageModel

    var body: some View {
        // The picture beside the words when there's room for both; in a narrow window the words alone (the page's own
        // pictures are further down).
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: Theme.Space.xl) {
                words.frame(minWidth: 300, idealWidth: 300, maxWidth: .infinity, alignment: .leading)
                if let image = hero.image, let folder = model.folder {
                    ExtensionPictureView(name: image, folder: folder, pixels: 640)
                        .frame(width: 256, height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line))
                        .shadow(color: Theme.navy.opacity(0.10), radius: 10, y: 4)
                }
            }
            words.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.card + 4, style: .continuous).fill(Theme.surfaceRaised)
            // The state's colour as a soft wash from the leading edge, so a glance tells ready from paused from wrong.
            RoundedRectangle(cornerRadius: Theme.Radius.card + 4, style: .continuous)
                .fill(LinearGradient(colors: [hero.tone.soft, hero.tone.soft.opacity(0)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card + 4, style: .continuous).strokeBorder(hero.tone == .neutral ? Theme.line : hero.tone.color.opacity(0.35)))
        .shadow(color: Theme.navy.opacity(0.06), radius: 12, y: 3)
        .accessibilityElement(children: .contain)
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                Image(systemName: hero.symbol ?? hero.tone.symbol)
                    .font(.system(size: 22, weight: .semibold)).foregroundStyle(hero.tone == .neutral ? Theme.accent : hero.tone.color)
                    .frame(width: 46, height: 46)
                    .background(hero.tone == .neutral ? Theme.accentSoft : hero.tone.soft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    if hero.eyebrow != nil || hero.busy {
                        HStack(spacing: 6) {
                            if hero.busy { ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 12, height: 12) }
                            else { Circle().fill(hero.tone == .neutral ? Theme.inkFaint : hero.tone.color).frame(width: 7, height: 7) }
                            if let eyebrow = hero.eyebrow {
                                // Yellow words on a pale wash are hard to read: a warning says it with its dot.
                                Text(verbatim: eyebrow).font(Theme.Font.captionStrong)
                                    .foregroundStyle(hero.tone == .neutral || hero.tone == .warn ? Theme.inkMuted : hero.tone.color)
                            }
                        }
                    }
                    Text(verbatim: hero.title).font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                    if let detail = hero.detail {
                        Text(verbatim: detail).font(Theme.Font.body).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let code = hero.code {
                Text(verbatim: code).font(.system(size: 46, weight: .semibold, design: .monospaced)).tracking(4).foregroundStyle(Theme.ink)
                    .padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.s)
                    .background(Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .textSelection(.enabled)
                    .accessibilityLabel(Text(verbatim: code.map { String($0) }.joined(separator: " ")))
            }
            if !hero.facts.isEmpty {
                HStack(alignment: .top, spacing: Theme.Space.xl) {
                    ForEach(Array(hero.facts.enumerated()), id: \.offset) { _, fact in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: fact.value).font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundStyle(Theme.ink)
                                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                            Text(verbatim: fact.label).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(1)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            if !hero.actions.isEmpty {
                FlowRow(spacing: Theme.Space.s) {
                    ForEach(Array(hero.actions.enumerated()), id: \.offset) { _, c in
                        PageButton(control: c, model: model, large: true, leads: !(model.page?.hasPrimary ?? true))
                    }
                }
                .padding(.top, Theme.Space.xs)
            }
        }
    }
}

// MARK: Transport

/// Something playing: where it is on a bar with the times, and its buttons as round symbols, the primary one (play or
/// pause) larger in the middle of them.
struct TransportView: View {
    var transport: ExtensionPage.Transport
    var model: ExtensionPageModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if transport.title != nil || transport.detail != nil {
                HStack(spacing: Theme.Space.s) {
                    if transport.state == .buffering { ProgressView().controlSize(.small) }
                    VStack(alignment: .leading, spacing: 2) {
                        if let title = transport.title { Text(verbatim: title).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink).lineLimit(2) }
                        if let detail = transport.detail { Text(verbatim: detail).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted) }
                    }
                }
            }
            if let position = transport.position {
                VStack(spacing: 4) {
                    if let duration = transport.duration {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.surfaceSunken)
                                Capsule().fill(Theme.accent).frame(width: max(6, geo.size.width * min(1, position / duration)))
                            }
                        }
                        .frame(height: 6)
                    }
                    HStack {
                        Text(verbatim: Self.clock(position))
                        Spacer()
                        if let duration = transport.duration { Text(verbatim: Self.clock(duration)) }
                    }
                    .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).monospacedDigit()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: Self.clock(position) + (transport.duration.map { " / " + Self.clock($0) } ?? "")))
            }
            HStack(spacing: Theme.Space.l) {
                Spacer(minLength: 0)
                ForEach(Array(transport.buttons.enumerated()), id: \.offset) { _, c in RoundButton(control: c, model: model) }
                Spacer(minLength: 0)
            }
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    static func clock(_ seconds: Double) -> String {
        let t = Int(max(0, seconds))
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
    }
}

private struct RoundButton: View {
    var control: ExtensionPage.Control
    var model: ExtensionPageModel
    @State private var running = false

    var body: some View {
        let primary = control.style == .primary
        let size: CGFloat = primary ? 52 : 38
        Button {
            running = true
            Task {
                await model.run(control, on: nil)
                running = false
            }
        } label: {
            Image(systemName: control.symbol ?? "circle")
                .font(.system(size: primary ? 20 : 15, weight: .semibold))
                .foregroundStyle(primary ? Theme.onAccent : control.style == .destructive ? Theme.danger : Theme.ink)
                .frame(width: size, height: size)
                .background(primary ? Theme.accent : Theme.surfaceRaised, in: Circle())
                .overlay { if !primary { Circle().strokeBorder(Theme.line) } }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(running || control.disabled ? 0.45 : 1)
        .disabled(running || control.disabled)
        .help(Text(verbatim: control.label))
        .accessibilityLabel(Text(verbatim: control.label))
    }
}
