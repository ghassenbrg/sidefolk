import SidefolkCore
import SwiftUI

/// The Play panel (D75): a small board beside the companion, drawn by Sidefolk from the game's data. The header says
/// whose game it is (the extension's badge, so it can never pass for Sidefolk's own cards), the score, the speaker
/// and ✕; the body is the board; a quiet line of keys sits under it.
struct PlayView: View {
    var model: PlayModel
    var onSpeaker: () -> Void = {}

    static let width: CGFloat = 360
    static let accent = Theme.folkColor("play")

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PlayHeader(model: model, onSpeaker: onSpeaker)
            if let failure = model.failure {
                failed(failure)
            } else if let board = model.board {
                BoardView(model: model, board: board)
            } else {
                HStack {
                    Spacer()
                    ProgressView().controlSize(.small)
                    Spacer()
                }
                .frame(height: 120)
            }
            Text(verbatim: model.footer)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.inkFaint)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(16)
        .frame(width: Self.width)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.surface)
                .overlay(alignment: .top) {
                    // A soft band along the top: this panel is for play. The app's accent, so no warm red reads as a loss.
                    LinearGradient(colors: [Theme.accent.opacity(0.14), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 70)
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22, style: .continuous))
                }
                .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.line, lineWidth: 1) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: model.info.title))
    }

    private func failed(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "gamecontroller").font(.system(size: 30, weight: .semibold)).foregroundStyle(Theme.inkMuted)
            Text(verbatim: message).font(Theme.Font.body).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
            Button(String(localized: "Close", comment: "Closes the Play panel")) { model.onClose?() }.buttonStyle(.sf(.secondary))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

/// The game's name and whose it is, the score, the speaker and ✕.
struct PlayHeader: View {
    var model: PlayModel
    var onSpeaker: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(LinearGradient(colors: [PlayView.accent.opacity(0.75), PlayView.accent], startPoint: .top, endPoint: .bottom))
                    Image(systemName: model.info.symbol ?? "gamecontroller.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                }
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: model.info.title).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink).lineLimit(1)
                    if !model.info.isSidefolk {
                        HStack(spacing: 4) {
                            ExtensionBadge(look: ExtensionLook(name: model.info.extensionName, iconPath: model.info.iconPath, folk: "play"), size: 13)
                            Text(verbatim: model.info.extensionName).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 4)
                Button(action: onSpeaker) {
                    Image(systemName: model.soundsOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 13, weight: .semibold)).frame(width: 28, height: 28)
                        .foregroundStyle(model.soundsOn ? Theme.ink : Theme.inkMuted)
                        .background(Circle().fill(Theme.surfaceSunken))
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help(model.soundsOn ? String(localized: "Turn the game's sounds off") : String(localized: "Turn the game's sounds on"))
                .accessibilityLabel(model.soundsOn ? String(localized: "Turn the game's sounds off") : String(localized: "Turn the game's sounds on"))
                Button { model.onClose?() } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).frame(width: 28, height: 28)
                        .foregroundStyle(Theme.inkMuted).background(Circle().fill(Theme.surfaceSunken))
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help(String(localized: "Close", comment: "Closes the Play panel"))
                .accessibilityLabel(String(localized: "Close", comment: "Closes the Play panel"))
            }
            if let score = model.board?.score {
                ScorePills(score: score, companionName: model.companionName, portrait: model.portrait)
            }
        }
    }
}

/// "You 3 · Mochi 2", round pips for a match, a streak flame, and the companion's sealed pick.
struct ScorePills: View {
    var score: GameBoard.Score
    var companionName: String
    var portrait: NSImage?

    var body: some View {
        HStack(spacing: 8) {
            pill {
                Text(String(localized: "You", comment: "The person, on a game's score")).font(Theme.Font.captionStrong)
                tally(score.you, won: .win)
            }
            .accessibilityElement(children: .combine)
            pill {
                GameAvatar(portrait: portrait, size: 18)
                Text(verbatim: companionName).font(Theme.Font.captionStrong).lineLimit(1)
                tally(score.companion, won: .loss)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            if let streak = score.streak, streak >= 2 {
                // A streak is the person's winning run: success, with its flame.
                HStack(spacing: 3) {
                    Image(systemName: "flame.fill").foregroundStyle(GameColors.color(.win))
                    Text(verbatim: Toss.number(streak)).font(Theme.Font.captionStrong).monospacedDigit()
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(Theme.successSoft))
                .accessibilityLabel(String(localized: "\(streak) in a row", comment: "A streak in a game"))
            }
            if score.companionPicked {
                SealedCard(portrait: portrait)
                    .accessibilityLabel(String(localized: "\(companionName) has picked", comment: "The companion chose its answer and keeps it hidden"))
            }
        }
        .foregroundStyle(Theme.ink)
    }

    /// Rounds won, as pips: the person's in the win colour, the companion's (the person's losses) in the calm loss tone.
    @ViewBuilder private func tally(_ n: Int, won: GameVerdict) -> some View {
        if let rounds = score.rounds {
            HStack(spacing: 3) {
                ForEach(0..<rounds, id: \.self) { i in
                    Circle().fill(i < n ? GameColors.color(won) : Theme.line).frame(width: 8, height: 8)
                }
            }
            .accessibilityLabel(Text(verbatim: Toss.number(n)))
        } else {
            Text(verbatim: Toss.number(n)).font(.system(size: 13, weight: .heavy, design: .rounded)).monospacedDigit()
                .contentTransition(.numericText())
        }
    }

    private func pill<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 5, content: content)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(Theme.surfaceSunken))
    }
}

/// The companion's face, round.
struct GameAvatar: View {
    var portrait: NSImage?
    var size: CGFloat

    var body: some View {
        Group {
            if let portrait { Image(nsImage: portrait).resizable().scaledToFill() } else { Circle().fill(PlayView.accent.opacity(0.4)) }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

/// A small card face down with the companion's face on it: it has picked and isn't telling.
struct SealedCard: View {
    var portrait: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(LinearGradient(colors: [Theme.navy, Theme.navy.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.white.opacity(0.7), lineWidth: 1.5).padding(2)
            GameAvatar(portrait: portrait, size: 14)
        }
        .frame(width: 22, height: 30)
        .rotationEffect(.degrees(-8))
        .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
        .transition(.scale.combined(with: .opacity))
    }
}
