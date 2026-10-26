import SidefolkCore
import SwiftUI

/// The top of Now: the day and a greeting on a quiet aqua-to-blue wash, your companion standing
/// beside them, and the thing you most often came for, asking it something (D33).
struct NowHero: View {
    var greeting: Text
    var status: Text
    var settings: AppSettings
    var ask: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Eyebrow(Text(verbatim: Date().formatted(.dateTime.weekday(.wide).day().month(.wide))))
                greeting.font(Theme.Font.hero).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                status.font(Theme.Font.body).foregroundStyle(Theme.inkMuted)
                Button(action: ask) {
                    Label("Ask \(settings.companionName)…", systemImage: "bubble.left.fill")
                }
                .buttonStyle(.sf(.primary, compact: false))
                .padding(.top, Theme.Space.m)
            }
            .padding(.vertical, Theme.Space.xl)
            Spacer(minLength: 0)
            // The rig's canvas leaves room around the body: pull it in so the companion stands just
            // above the card's bottom edge, as tall as the greeting beside it.
            CompanionPortrait(settings: settings, side: 176)
                .padding(.bottom, -10)
                .padding(.top, -Theme.Space.xl)
        }
        .padding(.leading, Theme.Space.xl)
        .padding(.trailing, Theme.Space.l)
        .background(LinearGradient(colors: [Theme.heroStart, Theme.heroEnd], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous).strokeBorder(Theme.line))
        .accessibilityElement(children: .contain)
    }
}
