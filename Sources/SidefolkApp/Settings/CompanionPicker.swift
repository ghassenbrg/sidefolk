import SidefolkCore
import SwiftUI

/// Settings › Companion's first group: three cards showing the companions as they are drawn on
/// the desktop, and the robot's light colour. Changes apply live (DECISIONS D27).
struct CompanionPicker: View {
    var model: SettingsModel

    private var settings: AppSettings { model.settings }

    var body: some View {
        SettingsGroup(title: "Companion", footer: footer) {
            HStack(spacing: Theme.Space.m) {
                ForEach(CompanionChoice.allCases, id: \.self) { choice in
                    CompanionCard(choice: choice,
                                  image: CompanionArt.preview(choice, accent: settings.accent, side: Self.preview),
                                  selected: settings.companion == choice) {
                        model.update { $0.choose(choice) }
                    }
                }
            }
            .padding(Theme.Space.m)
            if settings.companion == .sidefolk {
                SettingsRow(title: "Light colour", detail: "Its eyes, ear pods and the marks it makes.") {
                    AccentSwatches(selected: settings.accent) { accent in model.update { $0.accent = accent } }
                }
            }
        }
    }

    private static let preview: CGFloat = 112

    private var footer: String {
        settings.hasCustomName
            ? "Your companion is called “\(settings.companionName)” whichever one you pick. Change it in General."
            : "Picking another companion changes its name too. Choose your own name in General."
    }
}

/// One companion: its idle pose, its name and what it is.
private struct CompanionCard: View {
    var choice: CompanionChoice
    var image: NSImage?
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Theme.Space.xs) {
                Group {
                    if let image {
                        Image(nsImage: image).resizable().scaledToFit()
                    } else {
                        Text("Its art isn't in this build.").font(Theme.Font.caption).foregroundStyle(Theme.inkFaint)
                            .multilineTextAlignment(.center).padding(Theme.Space.s)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 112)
                .background(Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                Text(choice.defaultName).font(selected ? Theme.Font.bodyStrong : Theme.Font.body).foregroundStyle(Theme.ink)
                Text(blurb).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                    .multilineTextAlignment(.center).lineLimit(2, reservesSpace: true)
            }
            .padding(Theme.Space.s)
            .background(selected ? Theme.accentSoft : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(selected ? Theme.accent : Theme.line, lineWidth: selected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(image == nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(choice.defaultName), \(blurb)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var blurb: String {
        switch choice {
        case .sidefolk: "Robot with a glowing visor"
        case .mochi: "Bunny in a mint scarf"
        case .spark: "Robot with headphones"
        }
    }
}

/// The brand colours the robot's light can take.
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

    private func name(_ accent: CompanionAccent) -> String {
        switch accent {
        case .aqua: "Aqua"
        case .coral: "Coral"
        case .mint: "Mint"
        case .lightBlue: "Light blue"
        }
    }
}
