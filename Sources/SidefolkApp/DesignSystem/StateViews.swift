import SidefolkCore
import SwiftUI

/// What a thing is doing, said with a word (D78, D84): the colour follows `StatusTone` and is never the only signal.
/// `live` is Lantern's working light (busy is not an outcome, so it isn't green): a dot of glow beside ink words.
enum BadgeState: Equatable {
    case tone(StatusTone)
    case live

    var dot: Color {
        switch self {
        case .tone(let tone): tone == .neutral ? Theme.inkFaint : Theme.color(tone)
        case .live: Theme.glow
        }
    }

    var ink: Color {
        switch self {
        case .tone(.neutral), .live: Theme.inkMuted
        case .tone(let tone): Theme.color(tone)
        }
    }
}

/// A dot and a word: "● Ready", "● Needs you", "● Working", "● Stopped after crashing".
struct StatusBadge: View {
    var text: Text
    var state: BadgeState

    init(_ text: Text, state: BadgeState) {
        self.text = text
        self.state = state
    }

    init(_ text: LocalizedStringKey, tone: StatusTone) {
        self.init(Text(text), state: .tone(tone))
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(state.dot).frame(width: 7, height: 7)
                .overlay { if state == .live { Circle().strokeBorder(Theme.glow.opacity(0.35), lineWidth: 3).padding(-3) } }
            text.font(Theme.Font.captionStrong).foregroundStyle(state.ink).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// How many wait: amber with dark figures when they wait on the person (the same count as the shoulder badge), a
/// well when it only counts. Over 99 it says 99+.
struct CountBadge: View {
    var count: Int
    var waiting = true

    var body: some View {
        Text(verbatim: count > 99 ? "99+" : count.formatted())
            .font(.system(size: 11, weight: .bold).monospacedDigit())
            .foregroundStyle(waiting ? Color(hex: 0x2A1A00) : Theme.inkMuted)
            .padding(.horizontal, 6)
            .frame(minWidth: 18, minHeight: 18)
            .background(waiting ? Theme.waitGlow : Theme.well, in: Capsule())
            .accessibilityLabel(Text("\(count) waiting", comment: "A count of things waiting on the person, read by VoiceOver"))
    }
}

/// A state as a large word on a tile ("Changed", "Having trouble", "Paused"), in its tone's colour; neutral is ink.
struct StateWord: View {
    var text: Text
    var tone: StatusTone

    var body: some View {
        text.font(Theme.Font.stateWord).foregroundStyle(tone == .neutral ? Theme.ink : Theme.color(tone))
            .lineLimit(1).minimumScaleFactor(0.7)
    }
}

/// A tile on Today or a page (Lantern's tile, D84): where it comes from, a state word or a big number, one meta line and
/// an optional sparkline. The tone shows only on the word and a 3 pt bar along the top.
struct StateTile: View {
    var source: Text
    var symbol: String
    var value: Text
    /// A state word in its tone, or a number (nil) in ink.
    var tone: StatusTone?
    var meta: Text?
    var spark: [Double] = []

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Label { source.lineLimit(1) } icon: { Image(systemName: symbol) }
                .font(Theme.Font.callout).foregroundStyle(Theme.inkMuted)
            HStack(alignment: .lastTextBaseline) {
                if let tone {
                    StateWord(text: value, tone: tone)
                } else {
                    value.font(Theme.Font.number).foregroundStyle(Theme.ink).lineLimit(1)
                }
                Spacer(minLength: 0)
                if spark.count > 1 { Sparkline(values: spark).frame(width: 56, height: 22) }
            }
            if let meta { meta.font(Theme.Font.callout).foregroundStyle(Theme.inkFaint).lineLimit(1) }
        }
        .padding(Theme.Space.l)
        .frame(minWidth: Theme.Size.tileMin, maxWidth: Theme.Size.tileMax, alignment: .leading)
        .background(Theme.surfaceRaised)
        .overlay(alignment: .top) {
            if let tone, tone != .neutral { Rectangle().fill(Theme.color(tone)).frame(height: 3) }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .elevation(.e1)
        .accessibilityElement(children: .combine)
    }
}

/// A live value on the desktop beside the companion (Lantern's pin, D84): a glass capsule with its symbol, label,
/// number and a small sparkline. Paused or stale greys the number and says so in place of the line.
struct PinCapsule: View {
    var symbol: String
    var label: Text
    var value: Text
    var spark: [Double] = []
    /// "paused", "2 h old": the number is greyed and this replaces the sparkline.
    var note: Text?

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkMuted)
            label.font(Theme.Font.callout).foregroundStyle(Theme.inkMuted).lineLimit(1)
            value.font(Theme.Font.headline.monospacedDigit()).foregroundStyle(note == nil ? Theme.ink : Theme.inkFaint).lineLimit(1)
            if let note {
                note.font(Theme.Font.callout).foregroundStyle(Theme.inkFaint)
            } else if spark.count > 1 {
                Sparkline(values: spark, color: Theme.glow).frame(width: 40, height: 14)
            }
        }
        .padding(.horizontal, Theme.Space.m + 2)
        .frame(height: Theme.Size.pin)
        .lanternGlass(radius: Theme.Size.pin / 2, elevation: .e2)
        .accessibilityElement(children: .combine)
    }
}

/// A folk's painting in a circle on its colour (Lantern's avatar, D84): 24, 32 or 48. A ring of glow while it is on duty.
struct FolkAvatar: View {
    var name: String
    var size: CGFloat = Theme.Size.avatar
    var live = false

    var body: some View {
        Circle().fill(Theme.folkColor(name).opacity(0.18))
            .overlay {
                if let art = FolkArt.image(name, size: size * 1.25) {
                    Image(nsImage: art).resizable().scaledToFit().frame(width: size * 1.25, height: size * 1.25).offset(y: size * 0.08)
                } else {
                    Image(systemName: FolkBadge.symbol(for: name)).font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(Theme.folkColor(name))
                }
            }
            .clipShape(Circle())
            .overlay { if live { Circle().strokeBorder(Theme.glow, lineWidth: 2) } }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
