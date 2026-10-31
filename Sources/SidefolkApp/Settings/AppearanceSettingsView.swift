import SidefolkCore
import SwiftUI

/// Settings › Appearance (D84): the theme, light or dark, density and Home's icons, in one place for how Sidefolk
/// looks. Themes dress the app; they never arrange it.
struct AppearanceSettingsView: View {
    var model: SettingsModel

    var body: some View {
        SettingsPage {
            ThemeSettingsGroup(model: model)

            SettingsGroup(title: Text(verbatim: SettingKey.lightOrDark.section)) {
                SettingsRow(title: Text(verbatim: SettingKey.lightOrDark.title), anchor: .lightOrDark) { AppearancePicker(model: model) }
                SettingsRow(.density) { DensityPicker(model: model) }
                // The theme says simple or colourful; the person may prefer the other (D67).
                SettingsRow(.homeIcons) {
                    SegmentedPicker("Icons in Home", selection: Binding(get: { model.settings.sidebarIcons }, set: { i in model.update { $0.sidebarIcons = i } }),
                                    segments: [
                        .init(ThemeLayout.Icons?.none, Text("As the theme", comment: "Settings › General › Icons in Home: follow the theme")),
                        .init(ThemeLayout.Icons?.some(.simple), Text("Simple", comment: "Settings › General › Icons in Home: glyphs")),
                        .init(ThemeLayout.Icons?.some(.colorful), Text("Colourful", comment: "Settings › General › Icons in Home: tiles and extensions' own icons")),
                    ])
                }
            }
        }
    }
}

/// Light, dark or the same as the Mac.
struct AppearancePicker: View {
    var model: SettingsModel

    var body: some View {
        SegmentedPicker("Appearance", selection: Binding(get: { model.settings.appearance }, set: { a in model.update { $0.appearance = a } }),
                        segments: [.init(AppAppearance.light, "Light", symbol: "sun.max"),
                                   .init(AppAppearance.dark, "Dark", symbol: "moon"),
                                   .init(AppAppearance.system, "Same as Mac", symbol: "circle.lefthalf.striped.horizontal")])
    }
}

/// Comfortable or compact spacing; the theme's own until one is chosen.
struct DensityPicker: View {
    var model: SettingsModel

    var body: some View {
        SegmentedPicker(Text(verbatim: SettingKey.density.title),
                        selection: Binding(get: { model.settings.density ?? ThemeStore.shared.style.tokens.type.density },
                                           set: { d in model.update { $0.density = d } }),
                        segments: [.init(ThemeTokens.Density.regular, Text("Comfortable", comment: "Settings › Appearance › Density")),
                                   .init(ThemeTokens.Density.compact, Text("Compact", comment: "Settings › Appearance › Density"))])
    }
}
