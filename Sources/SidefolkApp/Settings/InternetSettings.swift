import SidefolkCore
import SwiftUI

/// Settings › Privacy & Permissions: how Sidefolk reads the web and uses online services, and the sites and built-in
/// services the person allowed for good (D47). Addresses the person types never ask, so this is about the ones
/// Sidefolk writes itself.
struct InternetGroup: View {
    var model: SettingsModel
    @State private var newSite = ""
    @State private var siteError: UserFacingError?

    private var rule: InternetRule { model.policy.internet }

    var body: some View {
        SettingsGroup(title: "Using the internet",
                      footer: "For pages and online services Sidefolk picks itself; addresses you type never ask. Other agents and the extensions you added keep their own rules.") {
            ChoiceRow(title: "Ask each time",
                      detail: "Sidefolk asks every time it would read a page or use an online service you didn't name, and doesn't remember your answers.",
                      selected: rule == .askEachTime) { set(.askEachTime) }
            ChoiceRow(title: "Ask once for each site",
                      detail: "Choose “Always allow” on a card and that site, or a built-in service like Weather, goes without asking from then on, even after Sidefolk has read other pages.",
                      selected: rule == .oncePerSite) { set(.oncePerSite) }
            ChoiceRow(title: "Don't ask before reading",
                      detail: "Sidefolk reads pages and uses Weather and Currency without asking. Once it has read something from outside, a site you haven't allowed still asks: that's where a page could make it send your data.",
                      selected: rule == .withoutAsking) { set(.withoutAsking) }
            if model.policy.mode == .askEveryTime, rule != .askEachTime {
                Label("“Ask every time” is on above, so the sites you allowed ask too.", systemImage: "info.circle")
                    .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.Space.l)
                    .padding(.vertical, Theme.Space.s)
            }
        }
        SettingsGroup(title: "Sites and services you allowed",
                      footer: "These go without a card, even after Sidefolk has read other pages, unless the address has details after “?”. Remove one and Sidefolk asks again.") {
            if allowed.isEmpty {
                InlineEmpty(text: "None yet. Choose “Always allow” when Sidefolk asks, or add a site here.", systemImage: "globe")
            }
            ForEach(allowed) { grant in
                AllowedSiteRow(grant: grant, model: model)
            }
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(spacing: Theme.Space.s) {
                    TextField("Site", text: $newSite, prompt: Text(verbatim: "example.com"))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                        .onSubmit(addSite)
                        .accessibilityLabel("Site to allow")
                    Button("Allow Site", action: addSite)
                        .buttonStyle(.sf(.secondary))
                        .disabled(newSite.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let siteError { InlineError(error: siteError) }
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.m)
        }
    }

    /// Site grants and built-in services, newest first; the rest of the grants stay under "Always allowed".
    private var allowed: [Grant] { model.grants.filter(InternetGrants.isInternet) }

    private func set(_ rule: InternetRule) {
        Task { await model.setPolicy { $0.internet = rule } }
    }

    private func addSite() {
        let text = newSite
        Task {
            siteError = await model.allowSite(text)
            if siteError == nil { newSite = "" }
        }
    }
}

/// One allowed site ("example.com · Read a web page") or built-in service ("Weather · Open-Meteo").
private struct AllowedSiteRow: View {
    var grant: Grant
    var model: SettingsModel

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            if let ext = extensionInfo {
                ExtensionBadge(look: ext.look, size: 20)
            } else {
                Image(systemName: "globe").foregroundStyle(Theme.folkColor("scout")).frame(width: 20).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).font(Theme.Font.body).foregroundStyle(Theme.ink).lineLimit(1).truncationMode(.middle)
                Text(verbatim: detail).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
            Spacer(minLength: Theme.Space.s)
            Button("Remove") { Task { await model.revoke(grant) } }
                .buttonStyle(.sf(.secondary))
                .accessibilityLabel(Text("Remove \(title)", comment: "Stop allowing a site: “Remove example.com”"))
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.s + 2)
    }

    private var extensionId: String? { grant.scope.string("extension") }
    private var extensionInfo: ExtensionInfo? { extensionId.flatMap { id in model.extensions.first { $0.id == id } } }

    private var title: String {
        if let host = grant.scope.string("host") { return host }
        return extensionInfo?.name ?? extensionId ?? grant.tool
    }

    private var detail: String {
        var parts: [String] = []
        if let id = extensionId, let service = BuiltInServices.byExtension[id] {
            parts.append(String(localized: "goes only to \(service.name)", comment: "A built-in extension allowed for good: “goes only to Open-Meteo”"))
        } else {
            parts.append(String(localized: "reading pages", comment: "A site allowed for good: “example.com · reading pages · last used …”"))
        }
        parts.append(grant.lastUsedAt.map { String(localized: "last used \(TimeText.relative($0))", comment: "“last used 2 days ago”") }
            ?? String(localized: "not used yet"))
        return parts.joined(separator: " · ")
    }
}

/// Which "Always allow" grants the internet group lists instead of "Always allowed": reading a site, and the
/// built-in services. A site allowed for opening links or watching stays there, since it doesn't hold the same way.
enum InternetGrants {
    static let readTool = "web.fetch"

    static func isInternet(_ grant: Grant) -> Bool {
        if grant.scope.string("host") != nil { return grant.tool == readTool }
        return grant.scope.string("extension").map { BuiltInServices.byExtension[$0] != nil } ?? false
    }
}
