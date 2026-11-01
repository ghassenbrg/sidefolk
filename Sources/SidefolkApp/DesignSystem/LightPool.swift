import SwiftUI

/// The companion's state as light (D84): a soft pool at its feet, readable from across the room. Colour is never the
/// only signal: the shoulder badge carries the count, Focus's half circle and Quiet's moon, and VoiceOver hears the
/// state. Where it stands and when it changes is the desktop's (phase 2).
enum LightPoolState: Equatable {
    case idle, working, waiting(Int), alert, failed, focus, quiet

    /// 03-system's light table: the colour and how strong.
    var light: (color: Color, opacity: Double)? {
        switch self {
        case .idle, .quiet: nil
        case .working: (Theme.glow, 0.35)
        case .waiting: (Theme.waitGlow, 0.45)
        case .alert: (Theme.waitGlow, 0.6)
        case .failed: (Theme.danger, 0.35)
        case .focus: (Theme.inkFaint, 0.15)
        }
    }

    /// What VoiceOver says, plainly.
    var spoken: Text {
        switch self {
        case .idle: Text("Resting", comment: "The companion's state, read by VoiceOver: nothing going on")
        case .working: Text("Working", comment: "The companion's state, read by VoiceOver")
        case .waiting(let count): Text("Waiting for you: \(count)", comment: "The companion's state, read by VoiceOver, with how many things wait")
        case .alert: Text("Something needs a look", comment: "The companion's state, read by VoiceOver")
        case .failed: Text("Something failed", comment: "The companion's state, read by VoiceOver")
        case .focus: Text("Focus", comment: "The companion's state, read by VoiceOver: only what matters gets through")
        case .quiet: Text("Quiet", comment: "The companion's state, read by VoiceOver: only what's critical gets through")
        }
    }
}

/// The pool itself: an ellipse of light that breathes while the companion works. With Reduce Motion it is a still
/// colour; with Increase Contrast it is a 2 pt ring, which reads where a soft glow doesn't.
struct LightPool: View {
    var state: LightPoolState
    var width: CGFloat = 140
    /// A still colour, as Reduce Motion has it: for copies of the light (Home's nook), where a breath forever would
    /// redraw a whole window every frame for something the desktop already shows.
    var still = false
    /// How loud the person is while the microphone listens (0...1 in steps, D88): the light swells with the voice
    /// instead of breathing. Nil the rest of the time.
    var level: Double? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var breathing = false
    /// An alert's one pulse (600 ms), then steady.
    @State private var pulse = false

    var body: some View {
        ZStack {
            if let level = listening {
                // The voice's light: brighter and a little wider as the person speaks up, settling between words.
                let color = state.light?.color ?? Theme.glow
                Ellipse()
                    .fill(RadialGradient(colors: [color.opacity(0.22 + 0.5 * level), color.opacity(0)],
                                         center: .center, startRadius: 0, endRadius: width / 2))
                    .frame(width: width, height: width * 0.28)
                    .scaleEffect(0.92 + 0.26 * level)
                    .animation(.easeOut(duration: 0.12), value: level)
            } else if let light = state.light {
                if contrast == .increased {
                    Ellipse().strokeBorder(light.color, lineWidth: 2).frame(width: width * 0.8, height: width * 0.18)
                } else {
                    Ellipse()
                        .fill(RadialGradient(colors: [light.color.opacity(light.opacity), light.color.opacity(0)],
                                             center: .center, startRadius: 0, endRadius: width / 2))
                        .frame(width: width, height: width * 0.28)
                        .scaleEffect(breathes && breathing ? 1.08 : pulse ? 1.18 : 1)
                        .opacity(breathes && breathing ? 0.75 : 1)
                }
            }
        }
        .frame(width: width, height: width * 0.28)
        .onAppear { light() }
        .onChange(of: state) { breathing = false; light() }
        .accessibilityHidden(true)
    }

    private func light() {
        if breathes { withAnimation(Theme.Motion.breath) { breathing = true } }
        guard state == .alert, !reduceMotion, !still else { return }
        withAnimation(.easeOut(duration: 0.3)) { pulse = true } completion: {
            withAnimation(.easeIn(duration: 0.3)) { pulse = false }
        }
    }

    private var breathes: Bool { state == .working && !reduceMotion && !still && listening == nil }

    /// The voice's level, when the light may move with it (never with Reduce Motion or for a copy of the light; with
    /// Increase Contrast the ring stays, which reads where a soft glow doesn't).
    private var listening: Double? { reduceMotion || still || contrast == .increased ? nil : level }
}

/// The mark on the companion's shoulder: how many wait (amber), how many Focus holds (grey), or Focus's half circle and
/// Quiet's moon when nothing waits. 28 pt for a count, smaller for a symbol.
struct ShoulderBadge: View {
    var state: LightPoolState
    /// How many wait while a card asks (alert), or are held while focusing: Focus still says it, in grey (package B's
    /// note). `.waiting` carries its own.
    var count = 0

    var body: some View {
        switch state {
        case .waiting(let n) where n > 0:
            countBadge(n, waiting: true)
        case .alert where count > 0:
            countBadge(count, waiting: true)
        case .focus where count > 0:
            countBadge(count, waiting: false)
        case .focus:
            symbol(Theme.Symbol.focus)
        case .quiet:
            symbol(Theme.Symbol.quiet)
        default:
            EmptyView()
        }
    }

    private func countBadge(_ n: Int, waiting: Bool) -> some View {
        Text(verbatim: n > 99 ? "99+" : n.formatted())
            .font(.system(size: 13, weight: .bold).monospacedDigit())
            .foregroundStyle(waiting ? Color(hex: 0x2A1A00) : Theme.ink)
            .padding(.horizontal, 6)
            .frame(minWidth: Theme.Size.stackBadge, minHeight: Theme.Size.stackBadge)
            .background(waiting ? Theme.waitGlow : Theme.well, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.9), lineWidth: 2))
            .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
            .accessibilityLabel(Text("\(n) waiting", comment: "A count of things waiting on the person, read by VoiceOver"))
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.melody)
            .frame(width: 20, height: 20)
            .background(Theme.surfaceRaised, in: Circle())
            .overlay(Circle().strokeBorder(Theme.line))
            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
            .accessibilityHidden(true)
    }
}

extension Theme {
    /// Focus belongs to Melody (focus); its symbols are drawn in Melody's colour beside the companion.
    static var melody: Color { folkColor("melody") }
}
