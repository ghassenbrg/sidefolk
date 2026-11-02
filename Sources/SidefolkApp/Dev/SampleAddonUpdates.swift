#if DEBUG
import SidefolkCore

/// Add-on updates waiting (D89), for UISnapshots: newer versions of add-ons in the sample gallery, one that would
/// let an extension do more, and Update all halfway (one updated, one updating), or done with its summary.
enum SampleAddonUpdates {
    static func newer(_ id: String, in catalog: AddonCatalog, version: String = "1.1.0") -> AddonEntry? {
        guard var entry = catalog.addons.first(where: { $0.id == id }) else { return nil }
        entry.version = version
        return entry
    }

    @MainActor static func show(in model: UpdateModel, catalog: AddonCatalog, halfway: Bool = true) {
        let companion = catalog.addons.first { $0.kind == .companion && $0.official }?.id ?? ""
        model.addonWaiting = [SampleAddons.newsstand, SampleAddons.pasteShelf, companion, "dev.sidefolk.themes.night-shift"]
            .compactMap { newer($0, in: catalog) }
        model.addonReview = [newer(SampleAddons.repoPal, in: catalog, version: "1.2.0")].compactMap { $0 }
        if halfway {
            model.addonRecent = model.addonWaiting.prefix(2).map { $0 }
            model.addonSteps = [model.addonWaiting[0].id: .updated, model.addonWaiting[1].id: .updating]
            model.addonWaiting.removeFirst()
        }
    }

    @MainActor static func clear(_ model: UpdateModel) {
        (model.addonWaiting, model.addonReview, model.addonRecent, model.addonSteps, model.addonSummary) = ([], [], [], [:], nil)
    }
}
#endif
