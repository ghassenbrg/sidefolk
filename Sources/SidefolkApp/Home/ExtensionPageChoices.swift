import SidefolkCore
import SwiftUI

/// A choice drawn as what it chooses between (D74): presets as cards with a line each, things on screen as pictures,
/// devices or accounts as rows with their state. The one picked is marked in the accent colour; picking another runs
/// the extension's tool with its value, through Guard, and shows the pick at once until the page confirms it.
struct PageChoiceView: View {
    var choice: ExtensionPage.Choice
    var model: ExtensionPageModel
    @State private var pending: String?
    @Environment(\.pageFlat) private var flat

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if !choice.hideLabel {
                Text(ext: choice.label).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
            }
            switch choice.style {
            case .cards:
                CardGrid(minWidth: 120, maxColumns: choice.options.count, spacing: Theme.Space.s) {
                    ForEach(choice.options, id: \.value) { option in OptionCard(option: option, picked: isPicked(option)) { pick(option) } }
                }
            case .tiles:
                CardGrid(minWidth: 170, maxColumns: choice.columns ?? 4, spacing: Theme.Space.m, stretch: choice.columns != nil) {
                    ForEach(choice.options, id: \.value) { option in
                        OptionTile(option: option, picked: isPicked(option), folder: model.folder, model: model) { pick(option) }
                    }
                }
            case .bar:
                PageChoiceBar(choice: choice, picked: pending ?? choice.selected, pick: pick)
            case .pills:
                PageChoicePills(choice: choice, picked: pending ?? choice.selected, pick: pick)
            case .menu:
                menu
            case .rows, .segmented:
                // In a section's card the rows stand apart, each tinted when picked, with no card of their own.
                if flat {
                    VStack(spacing: 2) {
                        ForEach(choice.options, id: \.value) { option in
                            OptionRow(option: option, picked: isPicked(option), folder: model.folder, model: model) { pick(option) }
                        }
                    }
                } else {
                    RowsCard {
                        ForEach(choice.options, id: \.value) { option in
                            OptionRow(option: option, picked: isPicked(option), folder: model.folder, model: model) { pick(option) }
                        }
                    }
                }
            }
            if let detail = choice.detail {
                Text(ext: detail).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
            }
        }
        .disabled(pending != nil || choice.disabled)
        .opacity(choice.disabled ? 0.6 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(ext: choice.label))
    }

    private var menu: some View {
        Menu {
            ForEach(choice.options, id: \.value) { option in
                Button { pick(option) } label: {
                    if isPicked(option) { Label { Text(ext: optionLine(option)) } icon: { Image(systemName: "checkmark") } } else { Text(ext: optionLine(option)) }
                }
            }
        } label: {
            HStack {
                Text(ext: choice.options.first { isPicked($0) }.map(optionLine) ?? choice.label).font(Theme.Font.body).foregroundStyle(Theme.ink).lineLimit(1)
                Spacer(minLength: Theme.Space.s)
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.inkMuted)
            }
            .padding(.horizontal, Theme.Space.m)
            .frame(minHeight: 38)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control + 2, style: .continuous).strokeBorder(Theme.line))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.sfBare)
        .menuIndicator(.hidden)
        .accessibilityLabel(Text(ext: choice.label))
    }

    private func optionLine(_ option: ExtensionPage.Choice.Option) -> String {
        option.detail.map { "\(option.label) · \($0)" } ?? option.label
    }

    private func isPicked(_ option: ExtensionPage.Choice.Option) -> Bool { (pending ?? choice.selected) == option.value }

    private func pick(_ option: ExtensionPage.Choice.Option) {
        guard option.value != choice.selected, pending == nil else { return }
        pending = option.value
        Task {
            if let go = choice.go(picking: option.value) { await model.go(go) } else { await model.run(tool: choice.tool, input: choice.input(picking: option.value)) }
            pending = nil
        }
    }
}

/// The accent ring and tick of the picked option.
private struct PickedMark: View {
    @Environment(\.pageSelected) private var pageAccent
    @Environment(\.colorScheme) private var colorScheme
    private var selection: PageSelection { PageSelection(accent: pageAccent, dark: colorScheme == .dark) }
    var picked: Bool
    /// One of a few rows in a card reads as a radio button.
    var radio = false

    var body: some View {
        Image(systemName: picked ? (radio ? "largecircle.fill.circle" : "checkmark.circle.fill") : "circle")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(picked ? selection.fill : Theme.inkFaint.opacity(0.6))
            .background(Circle().fill(picked ? Theme.surfaceRaised : .clear).padding(2))
    }
}

struct BadgeView: View {
    var badge: ExtensionPage.Badge

    var body: some View {
        Text(ext: badge.text).font(Theme.Font.captionStrong).lineLimit(1)
            .foregroundStyle(badge.tone == .neutral ? Theme.inkMuted : badge.tone.color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(badge.tone.soft, in: Capsule())
    }
}

private struct OptionCard: View {
    @Environment(\.pageSelected) private var pageAccent
    @Environment(\.colorScheme) private var colorScheme
    private var selection: PageSelection { PageSelection(accent: pageAccent, dark: colorScheme == .dark) }
    var option: ExtensionPage.Choice.Option
    var picked: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                if let symbol = option.symbol { Image(systemName: symbol).font(.system(size: 15)).padding(.bottom, 2) }
                Text(ext: option.label).font(Theme.Font.bodyStrong).foregroundStyle(picked ? selection.ink : Theme.ink).lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let detail = option.detail {
                    Text(ext: detail).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(2).multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, Theme.Space.s).padding(.vertical, Theme.Space.m)
            .background(picked ? selection.soft : Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.control + 2, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control + 2, style: .continuous)
                .strokeBorder(picked ? selection.fill : Theme.line, lineWidth: picked ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control + 2, style: .continuous))
        }
        .buttonStyle(.sfBare)
        .accessibilityLabel(Text(ext: [option.label, option.detail].compactMap { $0 }.joined(separator: ", ")))
        .accessibilityAddTraits(picked ? .isSelected : [])
    }
}

private struct OptionTile: View {
    @Environment(\.pageSelected) private var pageAccent
    @Environment(\.colorScheme) private var colorScheme
    private var selection: PageSelection { PageSelection(accent: pageAccent, dark: colorScheme == .dark) }
    var option: ExtensionPage.Choice.Option
    var picked: Bool
    var folder: URL?
    var model: ExtensionPageModel
    var action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Button(action: action) {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    ZStack(alignment: .topTrailing) {
                        // The frame's shape is 16:10 whatever the picture's; the picture fills it.
                        Color.clear
                            .aspectRatio(16 / 10, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .overlay { picture }
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.line))
                            .padding(3)
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(picked ? selection.fill : .clear, lineWidth: 2.5))
                        if picked { PickedMark(picked: true).padding(8) }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(ext: option.label).font(Theme.Font.bodyStrong).foregroundStyle(picked ? selection.ink : Theme.ink).lineLimit(1)
                            if let detail = option.detail {
                                Text(ext: detail).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                        if let badge = option.badge { BadgeView(badge: badge) }
                    }
                    .padding(.horizontal, 3)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.sfBare)
            .accessibilityLabel(Text(ext: [option.label, option.detail, option.badge?.text].compactMap { $0 }.joined(separator: ", ")))
            .accessibilityAddTraits(picked ? .isSelected : [])
            if let action = option.action { PageButton(control: action, model: model) }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder private var picture: some View {
        if let image = option.image, let folder {
            ExtensionPictureView(name: image, folder: folder, pixels: 480)
        } else {
            ZStack {
                Theme.surfaceSunken
                Image(systemName: option.symbol ?? "photo").font(.system(size: 26, weight: .light)).foregroundStyle(Theme.inkFaint)
            }
        }
    }
}

private struct OptionRow: View {
    @Environment(\.pageFlat) private var flat
    @Environment(\.pageSelected) private var pageAccent
    @Environment(\.colorScheme) private var colorScheme
    private var selection: PageSelection { PageSelection(accent: pageAccent, dark: colorScheme == .dark) }
    var option: ExtensionPage.Choice.Option
    var picked: Bool
    var folder: URL?
    var model: ExtensionPageModel
    var action: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Button(action: action) {
                HStack(spacing: Theme.Space.m) {
                    if let image = option.image, let folder {
                        ExtensionPictureView(name: image, folder: folder, pixels: 128)
                            .frame(width: 48, height: 30)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    } else if let symbol = option.symbol {
                        Image(systemName: symbol).font(.system(size: 15, weight: .medium))
                            .foregroundStyle(picked ? selection.fill : Theme.inkMuted)
                            .frame(width: 32, height: 32)
                            .background(picked ? Theme.surfaceRaised : Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ext: option.label).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink).lineLimit(1)
                        if let detail = option.detail {
                            Text(ext: detail).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(1)
                        }
                    }
                    Spacer(minLength: Theme.Space.s)
                    if let badge = option.badge { BadgeView(badge: badge) }
                    if !flat { PickedMark(picked: picked) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.sfBare)
            .accessibilityLabel(Text(ext: [option.label, option.detail, option.badge?.text].compactMap { $0 }.joined(separator: ", ")))
            .accessibilityAddTraits(picked ? .isSelected : [])
            if let action = option.action { PageButton(control: action, model: model) }
            // The marks line up down the card, whichever rows have a button.
            if flat {
                Button(action: action) { PickedMark(picked: picked, radio: true) }
                    .buttonStyle(.sfBare)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s + 2)
        .background(picked ? selection.soft.opacity(0.7) : .clear, in: RoundedRectangle(cornerRadius: flat ? 10 : 0, style: .continuous))
    }
}

/// Segments across the whole width: the pick filled in the page's accent, each with its symbol.
struct PageChoiceBar: View {
    var choice: ExtensionPage.Choice
    var picked: String
    var pick: (ExtensionPage.Choice.Option) -> Void
    @Environment(\.pageAccent) private var accent
    @Environment(\.pageAccentWords) private var words

    var body: some View {
        HStack(spacing: 2) {
            ForEach(choice.options, id: \.value) { option in
                let on = option.value == picked
                Button { pick(option) } label: {
                    HStack(spacing: 7) {
                        if let symbol = option.symbol { Image(systemName: symbol).font(.system(size: 14)) }
                        Text(ext: option.label).font(Theme.Font.body).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(on ? words : Theme.ink)
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(on ? (accent ?? Theme.accent) : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.sfBare)
                .accessibilityAddTraits(on ? .isSelected : [])
                .help(option.detail.map { Text(ext: $0) } ?? Text(ext: option.label))
            }
        }
        .padding(2)
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control + 2, style: .continuous).strokeBorder(Theme.line))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(ext: choice.label))
    }
}

/// Small rounded tabs: the pick tinted.
struct PageChoicePills: View {
    var choice: ExtensionPage.Choice
    var picked: String
    var pick: (ExtensionPage.Choice.Option) -> Void
    @Environment(\.pageSelected) private var accent
    @Environment(\.colorScheme) private var scheme
    private var selection: PageSelection { PageSelection(accent: accent, dark: scheme == .dark) }

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            ForEach(choice.options, id: \.value) { option in
                let on = option.value == picked
                Button { pick(option) } label: {
                    Text(ext: option.label).font(Theme.Font.body).lineLimit(1)
                        .foregroundStyle(on ? selection.ink : Theme.inkMuted)
                        .padding(.horizontal, Theme.Space.m).frame(minHeight: 32)
                        .background(on ? selection.soft : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.sfBare)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(ext: choice.label))
    }
}

/// A small choice at the end of a section's title: its pick tinted.
struct PageChoiceInline: View {
    var choice: ExtensionPage.Choice
    var model: ExtensionPageModel
    @State private var pending: String?

    var body: some View {
        PageChoicePills(choice: choice, picked: pending ?? choice.selected) { option in
            guard option.value != choice.selected, pending == nil else { return }
            pending = option.value
            Task {
                if let go = choice.go(picking: option.value) { await model.go(go) } else { await model.run(tool: choice.tool, input: choice.input(picking: option.value)) }
                pending = nil
            }
        }
        .disabled(pending != nil || choice.disabled)
    }
}
