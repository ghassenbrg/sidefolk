import SidefolkCore
import SwiftUI

// A game as a card, shared by the Play panel's menu and any other place that lists games (Playtime's page in Home):
// the same picture, colour and words everywhere, all drawn from the game's `GameLook` (D79 amended, the look v2).

/// A game's picture on a tile in its colour: Sidefolk's icon for its look, else its SF Symbol. Fills the frame given.
struct GameArtTile: View {
    var look: GameLook?
    var symbol: String?
    var corner: CGFloat = 14
    /// The picture grows a little under the pointer.
    var lifted = false

    var body: some View {
        let style = GameStyle.of(look)
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                style.gradient
                LinearGradient(colors: [.white.opacity(0.3), .clear], startPoint: .top, endPoint: .center)
                if let icon = style.icon, icon.image != nil {
                    icon.view(fitting: side * 0.86).shadow(color: .black.opacity(0.2), radius: 2.5, y: 2)
                        .scaleEffect(lifted ? 1.07 : 1).rotationEffect(.degrees(lifted ? -4 : 0))
                } else {
                    Image(systemName: symbol ?? "gamecontroller.fill").font(.system(size: side * 0.45, weight: .bold)).foregroundStyle(style.onColor)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// A heading over a group of games: "Play against <companion>" with its face, or "Puzzles" with a piece, on a band
/// tinted warm or cool.
struct GameSectionHeader: View {
    var title: String
    var solo: Bool
    var portrait: NSImage?

    var body: some View {
        let tint = solo ? Color(hex: 0x4D9BEA) : Theme.sun
        HStack(spacing: 8) {
            if !solo, portrait != nil {
                GameAvatar(portrait: portrait, size: 24).overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
            } else {
                Image(systemName: solo ? "puzzlepiece.fill" : "gamecontroller.fill").font(.system(size: 15, weight: .bold))
                    .foregroundStyle(tint).frame(width: 24, height: 24)
            }
            Text(verbatim: title).font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(GamePaint.card.opacity(0.95))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.16))))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tint.opacity(0.35), lineWidth: 1))
        .accessibilityAddTraits(.isHeader)
    }
}

/// A game on a menu: its picture tile, its title and tagline beside it, "Resume" when it was put away.
struct GameCard: View {
    var info: GameInfo
    var selected: Bool
    var resume: Bool
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                GameArtTile(look: info.look, symbol: info.symbol, corner: 13, lifted: hovered)
                    .frame(width: 54, height: 54)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: info.title).font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
                        .lineLimit(2).minimumScaleFactor(0.85).fixedSize(horizontal: false, vertical: true)
                    if resume {
                        Label(String(localized: "Resume", comment: "Play panel's menu: a game put away, opened where it was"), systemImage: "play.fill")
                            .font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(Theme.link).lineLimit(1)
                    } else if let tagline = info.tagline {
                        // A tagline is at most 60 characters: three short lines in German, never cut.
                        Text(verbatim: tagline).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(Theme.inkMuted)
                            .lineLimit(3).minimumScaleFactor(0.9).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(7)
            .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 17, style: .continuous).fill(GamePaint.card)
                .shadow(color: .black.opacity(hovered ? 0.14 : 0.07), radius: hovered ? 7 : 3, y: 2))
            .overlay {
                // The keyboard's choice: the app's accent, as any selection.
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .strokeBorder(selected ? Theme.accent : GamePaint.edge, lineWidth: selected ? 2.5 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .buttonStyle(GamePressStyle())
        .onHover { hovered = $0 }
        .animation(.spring(duration: 0.25, bounce: 0.4), value: hovered)
        .accessibilityLabel(Text(verbatim: [info.title, resume ? String(localized: "Resume", comment: "Play panel's menu: a game put away, opened where it was")
                                                               : info.tagline].compactMap { $0 }.joined(separator: ", ")))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
