import SidefolkCore
import SwiftUI

/// Settings › Privacy & Permissions: how Sidefolk reads the web and uses online services, and the sites and extensions'
/// services the person allowed for good (D47). Addresses the person types never ask, so this is about the ones
/// Sidefolk writes itself.
struct InternetGroup: View {
    var model: SettingsModel
    @State private var newSite = ""
    @State private var siteError: UserFacingError?

    private var rule: InternetRule { model.policy.internet }

    var body: some View {
        SettingsGroup(title: "Using the internet",
                      footer: "For pages and online services Sidefolk picks itself; addresses you type never ask. Other agents and the extensions you added keep their own rules.",
                      anchor: .internet) {
            ChoiceRow(title: "Ask each time",
                      detail: "Sidefolk asks every time it would read a page or use an online service you didn't name, and doesn't remember your answers.",
                      selected: rule == .askEachTime) { set(.askEachTime) }
            ChoiceRow(title: "Ask once for each site",
                      detail: "Choose “Always allow” on a card and that site, or a service one of Sidefolk's own extensions uses, goes without asking from then on, even after Sidefolk has read other pages.",
                      selected: rule == .oncePerSite) { set(.oncePerSite) }
            ChoiceRow(title: "Don't ask before reading",
                      detail: "Sidefolk reads pages and uses the services of its own extensions without asking. Once it has read something from outside, a site you haven't allowed still asks: that's where a page could make it send your data.",
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
                    TextField("Site", text: $newSite, prompt: Text(verbatim: "")).fieldHint(Text(verbatim: "example.com"), showing: newSite.isEmpty)
                        .lanternField()
                        .frame(maxWidth: 260)
                        .onSubmit(addSite)
                        .accessibilityLabel("Site to allow")
                    Button("Allow site", action: addSite)
                        .buttonStyle(.sf(.secondary))
                        .disabled(newSite.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let siteError { InlineError(error: siteError) }
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.m)
        }
        if !connecting.isEmpty {
            SettingsGroup(title: "Services your extensions connect to",
                          footer: "From each extension's manifest. Sidefolk signs its own, so it takes their word; anyone else's is only what they say, and their sandbox lets them reach any site.") {
                ForEach(connecting) { ExtensionServicesRow(ext: $0) }
            }
        }
    }

    /// Extensions that name their services, whoever made them (D98).
    private var connecting: [ExtensionInfo] { model.extensions.filter { !$0.services.isEmpty } }

    /// Site grants and extensions' services, newest first; the rest of the grants stay under "Always allowed".
    private var allowed: [Grant] { model.grants.filter { InternetGrants.isInternet($0, extensions: model.extensions) } }

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

/// One allowed site ("example.com · Read a web page") or an extension's service.
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
        if let services = extensionInfo?.services, !services.isEmpty {
            parts.append(String(localized: "goes only to \(Wording.list(services.map(\.name)))", comment: "An extension allowed for good: “goes only to Open-Meteo”"))
        } else {
            parts.append(String(localized: "reading pages", comment: "A site allowed for good: “example.com · reading pages · last used …”"))
        }
        parts.append(grant.lastUsedAt.map { String(localized: "last used \(TimeText.relative($0))", comment: "“last used 2 days ago”") }
            ?? String(localized: "not used yet"))
        return parts.joined(separator: " · ")
    }
}

/// Which "Always allow" grants the internet group lists instead of "Always allowed": Sidefolk reading a site, and
/// Sidefolk's own extensions' services. A site allowed for opening links or watching, or for other agents, stays there, since it
/// doesn't hold the same way.
enum InternetGrants {
    static let readTool = "web.fetch"

    static func isInternet(_ grant: Grant, extensions: [ExtensionInfo]) -> Bool {
        guard grant.callerKind == "agent" else { return false }
        if grant.scope.string("host") != nil { return grant.tool == readTool }
        guard let id = grant.scope.string("extension") else { return false }
        return extensions.contains { $0.id == id && $0.signedBySidefolk && !$0.services.isEmpty }
    }
}

/// An extension and the services and hosts its manifest names (D98), with whose word that is.
private struct ExtensionServicesRow: View {
    var ext: ExtensionInfo

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            ExtensionBadge(look: ext.look, size: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: ext.name).font(Theme.Font.body).foregroundStyle(Theme.ink)
                ForEach(ext.services, id: \.self) { service in
                    Text(verbatim: "\(service.name): \(service.hosts.joined(separator: ", "))")
                        .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
                }
                if !ext.signedBySidefolk {
                    Text("It says so itself; nothing holds it to this.", comment: "Settings › Trust: services named by an extension Sidefolk didn't sign")
                        .font(Theme.Font.caption).foregroundStyle(Theme.warning)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.s + 2)
        .accessibilityElement(children: .combine)
    }
}
