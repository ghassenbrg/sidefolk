import SidefolkCore
import SwiftUI

/// A choice drawn as what it chooses between (D74): presets as cards with a line each, things on screen as pictures,
/// devices or accounts as rows with their state. The one picked is marked in the accent colour; picking another runs
/// the extension's tool with its value, through Guard, and shows the pick at once until the page confirms it.
struct PageChoiceView: View {
    var choice: ExtensionPage.Choice
    var model: ExtensionPageModel
    @State private var pending: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: choice.label).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                if let detail = choice.detail {
                    Text(verbatim: detail).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
                }
            }
            switch choice.style {
            case .cards:
                CardGrid(minWidth: 120, maxColumns: choice.options.count, spacing: Theme.Space.s) {
                    ForEach(choice.options, id: \.value) { option in OptionCard(option: option, picked: isPicked(option)) { pick(option) } }
                }
            case .tiles:
                CardGrid(minWidth: 170, maxColumns: 4, spacing: Theme.Space.m, stretch: false) {
                    ForEach(choice.options, id: \.value) { option in
                        OptionTile(option: option, picked: isPicked(option), folder: model.folder, model: model) { pick(option) }
                    }
                }
            case .rows, .segmented:
                RowsCard {
                    ForEach(choice.options, id: \.value) { option in
                        OptionRow(option: option, picked: isPicked(option), folder: model.folder, model: model) { pick(option) }
                    }
                }
            }
        }
        .disabled(pending != nil || choice.disabled)
        .opacity(choice.disabled ? 0.6 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: choice.label))
    }

    private func isPicked(_ option: ExtensionPage.Choice.Option) -> Bool { (pending ?? choice.selected) == option.value }

    private func pick(_ option: ExtensionPage.Choice.Option) {
        guard option.value != choice.selected, pending == nil else { return }
        pending = option.value
        Task {
            await model.run(tool: choice.tool, input: choice.input(picking: option.value))
            pending = nil
        }
    }
}

/// The accent ring and tick of the picked option.
private struct PickedMark: View {
    var picked: Bool

    var body: some View {
        Image(systemName: picked ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(picked ? Theme.accent : Theme.inkFaint.opacity(0.6))
            .background(Circle().fill(picked ? Theme.surfaceRaised : .clear).padding(2))
    }
}

private struct BadgeView: View {
    var badge: ExtensionPage.Badge

    var body: some View {
        Text(verbatim: badge.text).font(Theme.Font.captionStrong).lineLimit(1)
            .foregroundStyle(badge.tone == .neutral ? Theme.inkMuted : badge.tone.color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(badge.tone.soft, in: Capsule())
    }
}

private struct OptionCard: View {
    var option: ExtensionPage.Choice.Option
    var picked: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                if let symbol = option.symbol { Image(systemName: symbol).font(.system(size: 15)).padding(.bottom, 2) }
                Text(verbatim: option.label).font(Theme.Font.bodyStrong).foregroundStyle(picked ? Theme.accent : Theme.ink).lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let detail = option.detail {
                    Text(verbatim: detail).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(2).multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, Theme.Space.s).padding(.vertical, Theme.Space.m)
            .background(picked ? Theme.accentSoft : Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.control + 2, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control + 2, style: .continuous)
                .strokeBorder(picked ? Theme.accent : Theme.line, lineWidth: picked ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control + 2, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: [option.label, option.detail].compactMap { $0 }.joined(separator: ", ")))
        .accessibilityAddTraits(picked ? .isSelected : [])
    }
}

private struct OptionTile: View {
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
                                .strokeBorder(picked ? Theme.accent : .clear, lineWidth: 2.5))
                        if picked { PickedMark(picked: true).padding(8) }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: option.label).font(Theme.Font.bodyStrong).foregroundStyle(picked ? Theme.accent : Theme.ink).lineLimit(1)
                            if let detail = option.detail {
                                Text(verbatim: detail).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                        if let badge = option.badge { BadgeView(badge: badge) }
                    }
                    .padding(.horizontal, 3)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: [option.label, option.detail, option.badge?.text].compactMap { $0 }.joined(separator: ", ")))
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
                            .foregroundStyle(picked ? Theme.accent : Theme.inkMuted)
                            .frame(width: 32, height: 32)
                            .background(picked ? Theme.surfaceRaised : Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: option.label).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink).lineLimit(1)
                        if let detail = option.detail {
                            Text(verbatim: detail).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(1)
                        }
                    }
                    Spacer(minLength: Theme.Space.s)
                    if let badge = option.badge { BadgeView(badge: badge) }
                    PickedMark(picked: picked)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: [option.label, option.detail, option.badge?.text].compactMap { $0 }.joined(separator: ", ")))
            .accessibilityAddTraits(picked ? .isSelected : [])
            if let action = option.action { PageButton(control: action, model: model) }
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s + 2)
        .background(picked ? Theme.accentSoft.opacity(0.7) : .clear)
    }
}
