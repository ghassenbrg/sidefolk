import SwiftUI

/// The Sidecard (D84): one glass surface that grows out of the companion, in four sizes. These are its looks; where
/// it stands, how long it stays and what it answers are the desktop's (phase 2). Size says importance: a whisper is
/// gentle, a card asks for attention, the stack holds what waits, Ask is called.

/// Where the Sidecard's tail points, toward the companion's head: from the bottom edge (a card above the head) or a
/// side (Ask, Play and palettes beside it). `at` is how far along that edge, 0 to 1, in reading order.
nonisolated struct SidecardTail: Equatable {
    enum Edge { case bottom, leading, trailing }
    var edge: Edge
    var at: CGFloat = 0.5
}

/// The glass with its tail: a rounded rectangle and a small point toward the companion, one outline.
nonisolated struct SidecardShape: Shape {
    var radius: CGFloat
    var tail: SidecardTail?
    /// Mirrored for right to left, so "leading" and "at" follow the reading direction.
    var rightToLeft = false
    static let tailSize = CGSize(width: 16, height: 8)

    func path(in rect: CGRect) -> Path {
        var body = rect
        if let tail {
            switch tail.edge {
            case .bottom: body.size.height -= Self.tailSize.height
            case .leading, .trailing:
                body.size.width -= Self.tailSize.height
                if physicalLeft(tail.edge) { body.origin.x += Self.tailSize.height }
            }
        }
        var path = Path(roundedRect: body, cornerRadius: radius, style: .continuous)
        guard let tail else { return path }
        let half = Self.tailSize.width / 2
        var point = Path()
        switch tail.edge {
        case .bottom:
            let along = rightToLeft ? 1 - tail.at : tail.at
            let x = min(max(body.minX + body.width * along, body.minX + radius + half), body.maxX - radius - half)
            point.move(to: CGPoint(x: x - half, y: body.maxY - 0.5))
            point.addQuadCurve(to: CGPoint(x: x, y: rect.maxY), control: CGPoint(x: x - 2, y: body.maxY + 2))
            point.addQuadCurve(to: CGPoint(x: x + half, y: body.maxY - 0.5), control: CGPoint(x: x + 2, y: body.maxY + 2))
        case .leading, .trailing:
            let y = min(max(body.minY + body.height * tail.at, body.minY + radius + half), body.maxY - radius - half)
            let left = physicalLeft(tail.edge)
            let edgeX = left ? body.minX + 0.5 : body.maxX - 0.5, tipX = left ? rect.minX : rect.maxX
            let bend: CGFloat = left ? -2 : 2
            point.move(to: CGPoint(x: edgeX, y: y - half))
            point.addQuadCurve(to: CGPoint(x: tipX, y: y), control: CGPoint(x: edgeX + bend, y: y - 2))
            point.addQuadCurve(to: CGPoint(x: edgeX, y: y + half), control: CGPoint(x: edgeX + bend, y: y + 2))
        }
        path.addPath(point)
        return path
    }

    private func physicalLeft(_ edge: SidecardTail.Edge) -> Bool {
        (edge == .leading) != rightToLeft
    }
}

/// Glass, the panel corner and e3 around any content, with an optional tail. Every Sidecard size sits on it.
struct SidecardSurface<Content: View>: View {
    var tail: SidecardTail?
    var radius: CGFloat = Theme.Radius.panel
    var padding: CGFloat = Theme.Space.l
    @ViewBuilder var content: Content
    @Environment(\.layoutDirection) private var direction
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = SidecardShape(radius: radius, tail: tail, rightToLeft: direction == .rightToLeft)
        content
            .padding(padding)
            .padding(tailInsets)
            .background {
                ZStack {
                    if reduceTransparency {
                        shape.fill(Theme.surfaceRaised)
                    } else {
                        shape.fill(.regularMaterial)
                        shape.fill(scheme == .dark ? Color(hex: 0x181E2B, opacity: 0.7) : Color(hex: 0xFAFBFD, opacity: 0.72))
                    }
                    shape.stroke(contrast == .increased ? Theme.controlBorder : scheme == .dark ? Color.white.opacity(0.08) : Theme.line,
                                 lineWidth: 1)
                }
                .compositingGroup()
                .shadow(color: scheme == .dark ? .black.opacity(0.55) : Color(hex: 0x0F1E36, opacity: 0.18), radius: 24, y: 18)
            }
    }

    /// Room for the tail outside the content.
    private var tailInsets: EdgeInsets {
        guard let tail else { return EdgeInsets() }
        let h = SidecardShape.tailSize.height
        switch tail.edge {
        case .bottom: return EdgeInsets(top: 0, leading: 0, bottom: h, trailing: 0)
        case .leading: return EdgeInsets(top: 0, leading: h, bottom: 0, trailing: 0)
        case .trailing: return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: h)
        }
    }
}

/// The gentlest size: one line in a glass capsule, an optional folk's face and one quiet action ("Undo"). It stays
/// six seconds and waits while the pointer is on it; `timeLeft` (1 to 0) draws that as a thin line along its foot,
/// greyed while it waits. Long languages may wrap to two lines; beyond that it should be a card.
struct Whisper<Action: View>: View {
    var text: Text
    var folk: String?
    /// The companion's own face, when it speaks for itself (no folk).
    var face: NSImage? = nil
    var timeLeft: Double?
    var paused = false
    var tail: SidecardTail? = SidecardTail(edge: .bottom)
    @ViewBuilder var action: Action

    var body: some View {
        SidecardSurface(tail: tail, radius: 22, padding: 0) {
            HStack(spacing: Theme.Space.s) {
                if let folk { FolkAvatar(name: folk, size: Theme.Size.avatarSmall) } else if let face { CompanionFace(image: face) }
                text.font(Theme.Font.bubble).foregroundStyle(Theme.ink).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                action.buttonStyle(.sf(.quiet, size: .small))
            }
            .padding(.leading, folk == nil && face == nil ? Theme.Space.l : Theme.Space.s)
            .padding(.trailing, Action.self == EmptyView.self ? Theme.Space.l : Theme.Space.xs)
            .padding(.vertical, Theme.Space.s)
            .frame(maxWidth: Theme.Size.sidecardMax)
            .overlay(alignment: .bottom) {
                if let timeLeft {
                    GeometryReader { geo in
                        Capsule().fill(paused ? Theme.inkFaint.opacity(0.4) : Theme.glow)
                            .frame(width: geo.size.width * max(0, min(1, timeLeft)), height: 2)
                    }
                    .frame(height: 2)
                    .padding(.horizontal, 18)
                    .accessibilityHidden(true)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

extension Whisper where Action == EmptyView {
    init(text: Text, folk: String? = nil, face: NSImage? = nil, timeLeft: Double? = nil, paused: Bool = false,
         tail: SidecardTail? = SidecardTail(edge: .bottom)) {
        self.init(text: text, folk: folk, face: face, timeLeft: timeLeft, paused: paused, tail: tail) { EmptyView() }
    }
}

/// The companion's own face in a Sidecard's source line, where a folk's avatar would be: the portrait is already round.
struct CompanionFace: View {
    var image: NSImage
    var size: CGFloat = Theme.Size.avatarSmall

    var body: some View {
        Image(nsImage: image).resizable().scaledToFit().frame(width: size, height: size).accessibilityHidden(true)
    }
}

/// The header strip of a permission slip (D71's tone by source, D84): calm on the accent's soft fill when the person
/// asked or Sidefolk's own signed code acts; firm on amber when another app asks or outside content came first. Never
/// red: red is for what was blocked.
struct SidecardStrip: View {
    enum Tone { case calm, firm }
    var tone: Tone
    var text: Text
    var symbol: String?

    var body: some View {
        Label {
            text.fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol ?? (tone == .calm ? "checkmark.shield" : "hand.raised"))
        }
        .font(Theme.Font.callout.weight(.medium))
        .foregroundStyle(tone == .calm ? Theme.link : Theme.warning)
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone == .calm ? Theme.accentSoft : Theme.warningSoft)
    }
}

/// The card size: who it's from ("Tempo · reminder · every 2 h"), a title, up to three lines, anything the moment needs
/// (chips, a diff), then up to three actions with the primary last, at the trailing edge. A slip adds its strip on top.
/// 320 to 400 wide; a close button unless it needs an answer.
struct SidecardCard<Extra: View, Actions: View>: View {
    var folk: String?
    /// The companion's own face, when it speaks for itself (no folk).
    var face: NSImage? = nil
    var source: Text?
    var title: Text
    var message: Text?
    var strip: SidecardStrip?
    var tail: SidecardTail? = SidecardTail(edge: .bottom)
    var close: (() -> Void)?
    @ViewBuilder var extra: Extra
    @ViewBuilder var actions: Actions

    var body: some View {
        SidecardSurface(tail: tail, padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                if let strip { strip }
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    // With a source line the face sits on it; without one (a slip) the face stands beside the words,
                    // as the one asking.
                    let sourceLine = source != nil || close != nil
                    if sourceLine {
                        HStack(spacing: Theme.Space.s) {
                            if let folk { FolkAvatar(name: folk, size: Theme.Size.avatarSmall) } else if let face { CompanionFace(image: face) }
                            source?.font(Theme.Font.callout).foregroundStyle(Theme.inkMuted).lineLimit(1)
                            Spacer(minLength: 0)
                            if let close {
                                Button(action: close) { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)) }
                                    .buttonStyle(.sf(.plain, size: .small))
                                    .foregroundStyle(Theme.inkFaint)
                                    .accessibilityLabel(Text("Close", comment: "Closes a card beside the companion"))
                            }
                        }
                    }
                    HStack(alignment: .top, spacing: Theme.Space.m) {
                        if !sourceLine, let folk { FolkAvatar(name: folk, size: Theme.Size.avatar) }
                        VStack(alignment: .leading, spacing: Theme.Space.xs) {
                            title.font(Theme.Font.bubbleTitle).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                            if let message {
                                message.font(sourceLine ? Theme.Font.bubble : Theme.Font.callout).foregroundStyle(Theme.inkMuted).lineLimit(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            extra.padding(.top, Theme.Space.xs)
                        }
                    }
                    ButtonRow(spacing: Theme.Space.s) { actions }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.top, Theme.Space.xs)
                }
                .padding(Theme.Space.l)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        }
        .frame(minWidth: Theme.Size.sidecardMin, maxWidth: Theme.Size.sidecardMax)
        .accessibilityElement(children: .contain)
    }
}

extension SidecardCard where Extra == EmptyView {
    init(folk: String? = nil, face: NSImage? = nil, source: Text? = nil, title: Text, message: Text? = nil, strip: SidecardStrip? = nil,
         tail: SidecardTail? = SidecardTail(edge: .bottom), close: (() -> Void)? = nil, @ViewBuilder actions: () -> Actions) {
        self.init(folk: folk, face: face, source: source, title: title, message: message, strip: strip, tail: tail, close: close,
                  extra: { EmptyView() }, actions: actions)
    }
}

/// What waits, held: up to three cards fanned behind each other, the last of `items` in front. The count sits on the
/// companion's shoulder (`ShoulderBadge`).
struct SidecardStack: View {
    struct Item: Identifiable {
        var id: String
        var folk: String?
        var title: Text
        var meta: Text?
    }

    var items: [Item]

    var body: some View {
        let shown = Array(items.prefix(3))
        VStack(spacing: -10) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                let depth = CGFloat(shown.count - 1 - index)
                SidecardSurface(padding: 0) {
                    HStack(spacing: Theme.Space.s) {
                        if let folk = item.folk { FolkAvatar(name: folk, size: Theme.Size.avatarSmall) }
                        VStack(alignment: .leading, spacing: 1) {
                            item.title.font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink).lineLimit(1)
                            if let meta = item.meta { meta.font(Theme.Font.callout).foregroundStyle(Theme.inkFaint).lineLimit(1) }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Theme.Space.m)
                    .padding(.vertical, Theme.Space.s + 2)
                }
                // The ones behind sit back a little: narrower and further in.
                .padding(.horizontal, depth * 8)
                .zIndex(Double(index))
            }
        }
        .frame(width: Theme.Size.sidecardMin)
        .accessibilityElement(children: .contain)
    }
}
