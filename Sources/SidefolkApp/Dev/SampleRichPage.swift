#if DEBUG
import AppKit
import SidefolkCore

/// A fictional extension's page with every richer part (D100), for the UI snapshots: a neighbourhood birdwatchers' log. No real extension
/// goes here, so an extension's look stays its own.
enum SampleRichPage {
    static let id = "com.example.birdlog"
    static let info = ExtensionPageInfo(extensionId: id, extensionName: "Bird Log", page: "log", title: "Bird Log", symbol: "bird", refresh: 60)

    static let json = #"""
    {"summary": {"title": "12 species this week", "tone": "good"},
     "sections": [
      {"blocks": [{"type": "hero", "title": "Bird Log", "detail": "What came to your garden, and what might come next", "symbol": "bird",
                   "scene": {"pack": "art/garden.png", "dark": "art/garden-night.png"}, "figure": {"companion": "full"}, "says": "Anything new today?", "tile": ["#3C8D5A", "#2B6E45"], "wash": ["#3C8D5A", "#2B6E45"],
                   "actions": [{"type": "button", "label": "Log a sighting", "tool": "log", "style": "primary", "symbol": "plus"},
                               {"type": "button", "label": "All species", "tool": "list", "symbol": "square.grid.2x2.fill"}]}]},
      {"blocks": [{"type": "stats", "items": [
        {"label": "Species", "value": "48", "symbol": "bird.fill", "tone": "good"}, {"label": "This week", "value": "12", "symbol": "calendar", "tone": "info"},
        {"label": "Best streak", "value": "9 days", "symbol": "flame.fill", "color": "#E8691C"}, {"label": "Sightings", "value": "1,204", "symbol": "binoculars.fill"}]}]},
      {"title": "Today", "detail": "Sunday, November 1", "blocks": [{"type": "cards", "size": "small", "items": [
        {"title": "Morning count", "detail": "14 birds before nine", "picture": {"pack": "art/robin.png"}, "done": true, "actions": []},
        {"title": "Feeder check", "detail": "Not done yet", "symbol": "leaf.fill", "color": "#3C8D5A", "actions": [{"type": "button", "label": "Check", "tool": "feeder", "symbol": "play.fill", "shape": "round"}]}]}]},
      {"blocks": [{"type": "tabs", "selected": "garden", "tabs": [
        {"id": "garden", "label": "Garden", "symbol": "leaf", "badge": "3", "sections": [
          {"title": "In your garden", "picture": {"companion": "face"}, "banner": {"tint": "#3C8D5A"}, "blocks": [{"type": "cards", "items": [
            {"title": "Robin", "detail": "Sings at dawn, unafraid of anyone", "meta": "Seen 212 times · last at the feeder", "at": "2026-11-01T08:30:00Z",
             "picture": {"pack": "art/robin.png"}, "badge": {"text": "Regular", "tone": "good"},
             "actions": [{"type": "button", "label": "Log", "tool": "log", "symbol": "plus", "style": "accent"}, {"type": "button", "label": "Listen", "tool": "listen", "style": "plain"}],
             "menu": {"label": "Season", "items": [{"type": "button", "label": "Spring", "tool": "season"}, {"type": "button", "label": "Winter", "tool": "season"}]}},
            {"title": "Goldfinch", "detail": "Likes thistle seed", "meta": "Seen 37 times", "symbol": "bird.fill", "color": "#B98A1E",
             "actions": [{"type": "button", "label": "Log", "tool": "log", "symbol": "plus"}]}]}]}]},
        {"id": "marsh", "label": "Marsh", "symbol": "water.waves", "sections": [{"blocks": [{"type": "note", "text": "Nothing logged at the marsh yet."}]}]}]}]},
      {"blocks": [{"type": "badges", "title": "Milestones", "items": [
        {"title": "First robin", "detail": "Logged one", "symbol": "seal.fill", "earned": true},
        {"title": "Fifty species", "detail": "Almost there", "symbol": "rosette", "value": 48, "goal": 50},
        {"title": "A week of mornings", "symbol": "sunrise.fill", "earned": true}, {"title": "Night owl", "detail": "An owl after dark", "symbol": "moon.stars.fill", "value": 0, "goal": 1}]}]},
      {"blocks": [{"type": "recent", "title": "Lately", "items": [
        {"title": "Robin at the feeder", "detail": "Pair, both feeding", "at": "2026-11-01T08:30:00Z", "tone": "good"},
        {"title": "Sparrowhawk", "detail": "Scattered everyone", "at": "2026-10-31T15:10:00Z", "tone": "warn"},
        {"title": "Missed the morning count", "at": "2026-10-30T09:00:00Z", "tone": "neutral", "symbol": "minus.circle"}]}]},
      {"wide": true, "blocks": [{"type": "settings", "title": "Settings", "ai": true}]},
      {"title": "Seen where", "wide": true, "blocks": [{"type": "settings", "keys": ["region", "patch"], "grid": true, "pictures": {"region": {"pack": "art/robin.png"}, "patch": {"pack": "art/garden.png"}}}]}]}
    """#

    static let rows: [ExtensionSettingRow] = [
        ExtensionSettingRow(extensionId: id, key: "sounds", type: .switch, title: "Birdsong", detail: "Play a song when you log a species.", value: .bool(true)),
        ExtensionSettingRow(extensionId: id, key: "region", type: .choice, title: "Region", options: [.init(value: "north", title: "Northern Europe"), .init(value: "south", title: "Southern Europe")],
                            value: .string("north")),
        ExtensionSettingRow(extensionId: id, key: "patch", type: .choice, title: "Patch", options: [.init(value: "front", title: "Front"), .init(value: "back", title: "Back")],
                            value: .string("front"), listed: false),
        ExtensionSettingRow(extensionId: id, key: "goal", type: .number, title: "Weekly goal", minimum: 1, maximum: 50, step: 1, value: .number(10)),
        ExtensionSettingRow(extensionId: id, key: "name", type: .text, title: "Name on your log", value: .string("Back garden")),
    ]

    /// A page that draws its own look with a scene (D100), and a scroll box with text in today's styles.
    static let sceneJSON = #"""
    {"sections": [{"blocks": [{"type": "scene", "actions": {"open": {"tool": "open"}}, "scene": {"size": [640, 220], "nodes": [
      {"type": "shape", "w": 640, "h": 220, "corner": 16, "gradient": {"colors": [{"token": "accent", "alpha": 0.35}, {"token": "accent", "alpha": 0.05}], "from": [0, 0], "to": [1, 1]}},
      {"type": "text", "x": 24, "y": 18, "w": 400, "h": 44, "text": "A bird table for {companion}", "size": 26, "weight": "black", "italic": true, "align": "leading"},
      {"type": "text", "x": 24, "y": 62, "w": 400, "h": 44, "lines": 2, "align": "leading", "size": 14, "runs": [{"text": "Twelve species ", "weight": "bold"}, {"text": "this week, and a new one on Tuesday.", "color": "ink_muted"}]},
      {"type": "symbol", "x": 24, "y": 120, "w": 32, "h": 32, "name": "bird.fill", "weight": "black", "mode": "mono", "color": "accent"},
      {"type": "clock", "x": 64, "y": 120, "w": 90, "h": 32, "seconds": 4512, "running": false, "size": 17, "weight": "bold", "align": "leading"},
      {"type": "text", "x": 170, "y": 120, "w": 120, "h": 32, "text": "Old count", "strike": true, "color": "ink_muted"},
      {"type": "companion", "x": 500, "y": 80, "w": 120, "h": 130, "align": "bottom"},
      {"type": "group", "x": 420, "y": 20, "w": 64, "h": 64, "corner": 32, "clip": true, "children": [
        {"type": "shape", "shape": "ellipse", "w": 64, "h": 64, "fill": "#F0C040"},
        {"type": "companion", "x": 8, "y": 8, "w": 48, "h": 48, "figure": "face", "duotone": "#F0C040"}]},
      {"type": "group", "id": "open", "x": 24, "y": 166, "w": 150, "h": 40, "children": [{"type": "shape", "w": 150, "h": 40, "corner": 10, "fill": "accent"}, {"type": "text", "w": 150, "h": 40, "text": "Open the log", "weight": "semibold", "color": "on_accent"}],
       "area": {"id": "open", "label": "Open the log"}}]}}]}]}
    """#

    @MainActor static func sceneModel() -> ExtensionPageModel {
        let page = (try? ExtensionPage.parse((try? JSONDecoder().decode(JSONValue.self, from: Data(sceneJSON.utf8))) ?? .null)) ?? ExtensionPage()
        return ExtensionPageModel(info: info, page: page, history: [:], alerts: [], updated: Date())
    }

    @MainActor static func model() -> ExtensionPageModel {
        let page = (try? ExtensionPage.parse((try? JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))) ?? .null)) ?? ExtensionPage()
        let model = ExtensionPageModel(info: info, page: page, history: [:], alerts: [], updated: Date())
        model.settingRows = rows
        model.aiStatus = ExtensionAIStatus(purpose: "to write a line about a bird you name", dailyCap: 10, usedToday: 2, on: true)
        model.samplePicture = { picture in
            if case .companion(let figure) = picture {
                return figure == .face ? CompanionArt.avatar(for: AppSettings(), side: 56) : CompanionArt.portrait(for: AppSettings(), state: .listening, side: 220)
            }
            return swatch(picture)
        }
        return model
    }

    /// A soft sky and a hill, standing in for a pack's painting.
    private static func swatch(_ picture: PagePicture) -> NSImage {
        NSImage(size: NSSize(width: 420, height: 230), flipped: false) { rect in
            let night: Bool = if case .pack(let path, _) = picture { path.contains("night") } else { false }
            NSGradient(starting: night ? .systemIndigo : .systemTeal, ending: night ? .black : .systemGreen)?.draw(in: rect, angle: -90)
            NSColor.white.withAlphaComponent(0.25).setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.width * 0.3, y: -rect.height * 0.4, width: rect.width, height: rect.height * 0.9)).fill()
            return true
        }
    }

    static let drop = ExtensionDropAction(extensionId: id, extensionName: "Bird Log", key: "clip", title: "Add a birdsong", detail: "Keeps the clip with your log", symbol: "waveform",
                                          kinds: [.link], patterns: ["https://*.mp4", "https://*.m3u8", "https://*.mov"], tool: "ext.birdlog.add_clip", input: ["url": "{value}"])

    static let askEntry = ExtensionEntry(extensionId: id, extensionName: "Bird Log", key: "log", title: "Birds", symbol: "bird", places: [.ask], action: .page("log", state: nil), firstParty: true)
}
#endif
