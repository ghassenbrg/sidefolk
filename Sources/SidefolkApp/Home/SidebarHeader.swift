import AppKit
import SidefolkCharacter
import SidefolkCore
import SwiftUI

/// The top of Home's sidebar in a theme with a header picture (D130, D220): the companion stands on its light in a small
/// strip of its studio, and its name and state are on the plain sidebar below, where they always read. A short window has
/// no room for the picture, so it goes without, and the companion's face takes one line beside its name. Everything under
/// it is plain, for reading and scrolling. A click goes to Today.
struct SidebarHeader: View {
    var model: NowModel
    var compact = false

    var body: some View {
        let settings = model.services.runtime.settings.current
        Group {
            if compact {
                HStack(spacing: Theme.Space.s + 2) {
                    CompanionPortrait(settings: settings, state: pose, side: 34).frame(width: 36, height: 36)
                    words(settings)
                }
                .padding(.horizontal, Theme.Space.l)
                .padding(.vertical, Theme.Space.xs)
            } else {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SidebarStudio()
                        .overlay(alignment: .bottom) {
                            ZStack(alignment: .bottom) {
                                LightPool(state: model.poolState, width: 92, still: true).offset(y: 5)
                                CompanionPortrait(settings: settings, state: pose, side: 72)
                            }
                            .overlay(alignment: .topTrailing) { if model.poolState == .quiet { ShoulderBadge(state: .quiet).scaleEffect(0.7) } }
                            .frame(width: 96, height: 76)
                        }
                    words(settings).padding(.horizontal, Theme.Space.l)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, Theme.Space.xs)
        .contentShape(Rectangle())
        .help(Text(verbatim: line))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(settings.companionName). \(model.stateWord ?? "") \(line)"))
        .accessibilityHint(Text("Opens Today"))
    }

    // Always under the name: beside it where it fit, a long "next:" dropped it a line and moved every row below.
    private func words(_ settings: AppSettings) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: settings.companionName).font(Theme.Font.headline).foregroundStyle(Theme.sidebarInk).lineLimit(1).fixedSize()
            state
        }
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

/// The header's picture as a strip the sidebar's width: the furniture and the floor from a taller painting, its top and foot
/// fading into the sidebar so there's no seam (D220). Its height follows the width, so a wider sidebar doesn't crop it.
struct SidebarStudio: View {
    /// The strip's shape, and where it sits in the painting: from just above the furniture to just under the rug's middle.
    private static let shape: CGFloat = 2.3
    private static let foot: CGFloat = 0.9
    private static let painting: CGFloat = 800.0 / 566.0
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Color.clear
            .aspectRatio(Self.shape, contentMode: .fit)
            .overlay {
                if let art = Theme.Art.header(dark: scheme == .dark) {
                    GeometryReader { g in
                        let height = g.size.width / Self.painting
                        Image(decorative: art, scale: 2).resizable()
                            .frame(width: g.size.width, height: height)
                            .offset(y: g.size.height - height * Self.foot)
                    }
                    .clipped()
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.16),
                                                 .init(color: .black, location: 0.82), .init(color: .clear, location: 1)],
                                         startPoint: .top, endPoint: .bottom))
                }
            }
            .allowsHitTesting(false)
    }
}

/// The logo beside the window's buttons, when the theme has one: the brand's navy on light (its aqua "folk" doesn't read
/// there, D130), the reversed one on dark.
struct SidebarLogo: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if ThemeStore.shared.style.tokens.nook.logo, let mark = (scheme == .dark ? BrandAsset.wordmarkReversed : BrandAsset.wordmarkNavy).image {
            Image(nsImage: mark).resizable().scaledToFit().frame(height: 18)
                .padding(.top, 16).padding(.trailing, Theme.Space.m)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .allowsHitTesting(false)
                .accessibilityLabel("Sidefolk")
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
