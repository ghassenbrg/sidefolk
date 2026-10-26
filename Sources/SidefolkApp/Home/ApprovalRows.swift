import SidefolkCore
import SwiftUI

/// A step nobody answered in time (D37), in Now › Needs you: the question its card asked, word for
/// word, what happened instead, and "Run it now", which answers that question.
struct SkippedStepRow: View {
    var step: SkippedStep
    var run: () -> Void
    var dismiss: () -> Void
    /// Inert for a moment, like the card it stands in for.
    @State private var armed = false

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            IconTile(symbol: "clock.badge.xmark", folk: "guard")
            VStack(alignment: .leading, spacing: 3) {
                Text(step.request.title).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(step.request.summary).font(Theme.Font.body).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                ApprovalDetails(details: step.request.details)
                if step.request.tainted {
                    Label("This came up while reading outside content. Check it carefully.", systemImage: "exclamationmark.triangle")
                        .font(Theme.Font.caption).foregroundStyle(Theme.danger)
                }
                outcome.font(Theme.Font.caption).foregroundStyle(Theme.inkFaint)
                HStack(spacing: 6) {
                    Button("Run it now", action: run)
                        .buttonStyle(.sf(step.request.risk == .high ? .destructive : .primary))
                        .disabled(!armed)
                    Button("Dismiss", action: dismiss).buttonStyle(.sf(.plain))
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
        .accessibilityElement(children: .contain)
        .task {
            try? await Task.sleep(for: .milliseconds(800))
            armed = true
        }
    }

    private var outcome: Text {
        let time = TimeText.short(step.skippedAt)
        return step.stoppedTask ? Text("Nobody answered by \(time), so the task stopped here.")
            : Text("Nobody answered by \(time), so the task went on without it.")
    }
}

/// What the last "Run it now" did.
struct SkippedRunResult: View {
    var result: Result<String, UserFacingError>

    var body: some View {
        Group {
            switch result {
            case .success(let done):
                Label { Text("Done: \(done)") } icon: { Image(systemName: "checkmark.circle.fill") }.foregroundStyle(Theme.success)
            case .failure(let error):
                Label { Text(verbatim: error.message) } icon: { Image(systemName: "exclamationmark.circle.fill") }.foregroundStyle(Theme.danger)
            }
        }
        .font(Theme.Font.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.s + 2)
    }
}

/// While Full access is on, Now says so before anything else, with the way back (D37).
struct FullAccessBanner: View {
    var settings: () -> Void
    var turnOff: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.m) {
            Image(systemName: GuardMode.fullAccess.symbol)
                .foregroundStyle(Theme.onDanger)
                .frame(width: 28, height: 28)
                .background(Theme.danger, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Full access is on").font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                Text(verbatim: GuardMode.fullAccess.explanation).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Space.s)
            Button("Settings…", action: settings).buttonStyle(.sf(.secondary)).fixedSize()
            Button("Turn Off", action: turnOff).buttonStyle(.sf(.primary)).fixedSize()
        }
        .padding(Theme.Space.m)
        .background(Theme.dangerSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}
