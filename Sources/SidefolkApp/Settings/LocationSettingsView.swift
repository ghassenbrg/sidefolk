import SidefolkCore
import SwiftUI

/// Settings › Privacy › Your location (D48): whether Sidefolk knows where the person is, from what, and where it thinks
/// that is. Off until they choose.
struct LocationGroup: View {
    var model: LocationSettingsModel

    private var settings: LocationSettings { model.settings }

    var body: some View {
        SettingsGroup(title: "Your location", footer: "Only the town or city goes to your AI, never an address or coordinates. Weather lookups send the place to Open-Meteo, as for any place you ask about.") {
            ChoiceRow(title: "Off", detail: "Name a place when you ask about the weather.", selected: settings.source == .off) {
                model.choose(.off)
            }
            ChoiceRow(title: "Use my Mac's location", detail: "Your town, from Location Services. macOS asks you once.",
                      selected: settings.source == .mac) { model.choose(.mac) }
            if settings.source == .mac { MacPlaceRow(model: model) }
            ChoiceRow(title: "A place I choose", detail: "A town you pick by name, for when you'd rather not share the Mac's location.",
                      selected: settings.source == .chosen) { model.choose(.chosen) }
            if settings.source == .chosen { ChosenPlaceRows(model: model) }
        }
    }
}

/// Where the Mac's location says the person is, or why it can't say yet.
private struct MacPlaceRow: View {
    var model: LocationSettingsModel

    var body: some View {
        switch model.access {
        case .allowed:
            if let place = model.settings.place {
                SettingsRow(title: Text(verbatim: place.fullName), detail: Text("From your Mac's location, \(TimeText.relative(place.updatedAt))")) {
                    Chip("Allowed", tone: .success, systemImage: "location.fill")
                }
            } else {
                SettingsRow(title: "Finding where you are…", detail: "It takes a moment, and needs Wi-Fi to be on.") {
                    ProgressView().controlSize(.small)
                }
            }
        case .notAsked:
            SettingsRow(title: "Location Services", detail: "macOS hasn't asked you yet.") {
                Button("Allow…") { model.useMacLocation() }.buttonStyle(.sf(.primary))
            }
        case .denied:
            SettingsRow(title: "Location Services", detail: "Not allowed for Sidefolk. Allow it in System Settings, or choose a place instead.") {
                Button("Open System Settings") { model.openSystemSettings() }.buttonStyle(.sf(.primary))
            }
        }
    }
}

/// The town the person picked, and a search to pick one.
private struct ChosenPlaceRows: View {
    @Bindable var model: LocationSettingsModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        if let place = model.settings.place {
            SettingsRow(title: Text(verbatim: place.fullName), detail: Text("Chosen by you")) {
                Chip("Chosen", tone: .success, systemImage: "mappin.and.ellipse")
            }
        }
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                TextField("Town or city", text: $model.query, prompt: Text("Town or city, like Fukuoka or Austin, Texas"))
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                    .onSubmit { Task { await model.search() } }
                Button(model.settings.place == nil ? "Search" : "Change") { Task { await model.search() } }
                    .buttonStyle(.sf(.secondary))
                    .disabled(model.query.trimmingCharacters(in: .whitespaces).isEmpty || model.searching)
            }
            if model.searching {
                ProgressView().controlSize(.small)
            } else if let error = model.searchError {
                InlineError(error: error)
            } else if model.foundNothing {
                Text("No town by that name. Try the nearest city, or add the country.").font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
            }
            ForEach(model.results, id: \.self) { place in
                Button { model.pick(place) } label: {
                    HStack(spacing: Theme.Space.s) {
                        Image(systemName: "mappin").foregroundStyle(Theme.inkMuted).accessibilityHidden(true)
                        Text(verbatim: place.fullName).font(Theme.Font.body).foregroundStyle(Theme.ink)
                        Spacer(minLength: 0)
                        Text("Use", comment: "Picks this town as the person's place").font(Theme.Font.captionStrong).foregroundStyle(Theme.link)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Use \(place.fullName)", comment: "A button: “Use Portland, Oregon, United States”"))
            }
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
        .onAppear { if model.settings.place == nil { searchFocused = true } }
    }
}
