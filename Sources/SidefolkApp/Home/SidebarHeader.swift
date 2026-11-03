import AppKit
import SidefolkCharacter
import SidefolkCore
import SwiftUI

/// The top of Home's sidebar in a theme with a header picture (D130): the companion stands in the scene on its light, and
/// its name and state are on the plain sidebar below, where they always read. The picture ends here, and everything under
/// it is plain, for reading and scrolling. A click goes to Today. The picture itself is `SidebarHeaderArt`, up under the
/// toolbar behind the window's buttons.
struct SidebarHeader: View {
    var model: NowModel

    var body: some View {
        let settings = model.services.runtime.settings.current
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            ZStack(alignment: .bottom) {
                LightPool(state: model.poolState, width: 104, still: true).offset(y: 6)
                CompanionPortrait(settings: settings, state: pose, side: 84)
            }
            .overlay(alignment: .topTrailing) { if model.poolState == .quiet { ShoulderBadge(state: .quiet).scaleEffect(0.7) } }
            .frame(width: 110, height: 88)
            .frame(maxWidth: .infinity)
            .frame(height: SidebarHeaderArt.height - SidebarHeaderArt.toolbar - 4, alignment: .bottom)
            .padding(.bottom, Theme.Space.xs)
            // Always under the name: beside it where it fit, a long "next:" dropped it a line and moved every row below.
            VStack(alignment: .leading, spacing: 2) { name(settings); state }
                .padding(.horizontal, Theme.Space.l)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, Theme.Space.xs)
        .contentShape(Rectangle())
        .help(Text(verbatim: line))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(settings.companionName). \(model.stateWord ?? "") \(line)"))
        .accessibilityHint(Text("Opens Today"))
    }

    private func name(_ settings: AppSettings) -> some View {
        Text(verbatim: settings.companionName).font(Theme.Font.heading).foregroundStyle(Theme.sidebarInk).lineLimit(1).fixedSize()
    }

    /// What it's waiting on or doing, else what's next; the rest is in the help, not cut off here.
    @ViewBuilder private var state: some View {
        if let word = model.stateWord {
            Text(verbatim: word).font(Theme.Font.callout.weight(.medium)).lineLimit(1)
                .foregroundStyle(model.poolState == .waiting(0) || model.poolPose == .waiting ? Theme.warning : Theme.sidebarInkMuted)
        } else {
            // Cut in the middle: the time at its end is what the line is for.
            Text(verbatim: line).font(Theme.Font.callout).foregroundStyle(Theme.sidebarInkMuted).lineLimit(1).truncationMode(.middle)
        }
    }

    private var pose: CharacterState {
        switch model.poolPose {
        case .sleeping: .sleeping
        case .waiting: .waiting
        case .working: .working(.laptop)
        case .idle: .idle
        }
    }

    private var line: String {
        if let until = model.quietUntil {
            return String(localized: "Only urgent things until \(TimeFormat.clock(until, calendar: .current))",
                          comment: "The companion's nook while Quiet is on")
        }
        return model.nookLine
    }
}

/// The header's picture, behind the window's buttons, its foot fading into the sidebar. The logo, when the theme has one,
/// sits in the empty space beside those buttons: the brand's navy on light (its aqua "folk" doesn't read there, D130), the
/// reversed one on dark.
struct SidebarHeaderArt: View {
    static let height: CGFloat = 164
    /// Where the toolbar's row ends.
    static let toolbar: CGFloat = 52
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let art = Theme.Art.header(dark: scheme == .dark) {
            Color.clear.frame(height: Self.height)
                .overlay { Image(decorative: art, scale: 2).resizable().scaledToFill() }
                .clipped()
                .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.86), .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(alignment: .topTrailing) {
                    if ThemeStore.shared.style.tokens.nook.logo, let mark = (scheme == .dark ? BrandAsset.wordmarkReversed : BrandAsset.wordmarkNavy).image {
                        Image(nsImage: mark).resizable().scaledToFit().frame(height: 19)
                            .padding(.top, 15).padding(.trailing, Theme.Space.m)
                            .accessibilityLabel("Sidefolk")
                    }
                }
                .allowsHitTesting(false)
        }
    }
}

/// Turns off the list's own highlight, so the only selected row is the theme's (D130): `selectionHighlightStyle` is the
/// table's public switch, and selection, arrow keys, type-select, drag and VoiceOver all stay native. SwiftUI gives no way
/// to reach it but the view tree. If that tree changes, the system's highlight comes back under the theme's row, which is
/// a cosmetic loss and nothing worse.
struct SidebarHighlightOff: NSViewRepresentable {
    final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }
        override func layout() {
            super.layout()
            apply()
        }
        private func apply() {
            var view = superview
            while let next = view {
                if let table = next as? NSTableView {
                    if table.selectionHighlightStyle != .none { table.selectionHighlightStyle = .none }
                    return
                }
                view = next.superview
            }
        }
    }

    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ view: Probe, context: Context) {}
}

/// The theme's selected row, behind a row of the sidebar's list.
struct SidebarRowFill: View {
    var selected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
            .fill(selected ? Theme.sidebarSelected : .clear)
            .padding(.horizontal, Theme.Space.s + 2)
            .padding(.vertical, 1)
    }
}
