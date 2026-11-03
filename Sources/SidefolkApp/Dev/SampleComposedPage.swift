#if DEBUG
import Foundation
import SidefolkCore

/// A made-up extension showing a page composed like an app's screen: a head with its icon and state, a ring, cards side by side, a joined list and pane, metrics.
enum SampleComposedPage {
    private static let json = #"""
    {"bare": true, "max_width": 1180, "dress": {"ground": {"light": "#F5F7FB", "dark": "#161A22"}, "card": {"light": "#FFFFFF", "dark": "#1F242E"}, "line": {"light": "#E1E5EE", "dark": "#333A48"},
      "accent": {"light": "#2F66DD", "dark": "#7F9CFF"}, "selected": {"light": "#2F66DD", "dark": "#7F9CFF"}, "well": {"light": "#EEF1F8", "dark": "#2A303C"}},
     "sections": [
      {"wide": true, "blocks": [{"type": "bar", "brand": true, "title": "Tea Timer", "detail": "Two brews going", "pill": {"text": "Brewing", "tone": "good"}, "actions": [], "menu": []}]},
      {"wide": true, "blocks": [{"type": "hero", "plain": true, "title": "Ready at 16:40", "detail": "The green tea finishes first.", "tone": "neutral", "busy": false, "facts": [],
        "ring": {"fraction": 0.6, "value": "3 min", "caption": "left"}, "chips": [{"label": "Sound on", "symbol": "speaker.wave.2", "tone": "good"}],
        "actions": [{"type": "button", "label": "1 min more", "tool": "more", "symbol": "plus"}, {"type": "button", "label": "Stop", "tool": "stop", "style": "primary", "symbol": "stop.fill"}]}]},
      {"blocks": [{"type": "metric", "label": "Steeped", "value": "42", "symbol": "cup.and.saucer", "caption": "this week", "fraction": 0.7}, {"type": "metric", "label": "Water", "value": "96 °C", "symbol": "thermometer.medium", "tone": "warn", "caption": "Too hot for green"},
                  {"type": "metric", "label": "Left", "value": "12 bags", "symbol": "leaf", "size": "small"}]},
      {"title": "Teas", "joined": true, "row": "shelf", "weight": 41, "blocks": [
        {"type": "field", "search": true, "live": true, "label": "Search", "placeholder": "Search teas…", "button": "Clear", "key": "q", "go": {"set": {}}, "input": {}},
        {"type": "choice", "style": "pills", "label": "Which", "hide_label": true, "selected": "all", "key": "f", "go": {"set": {}}, "input": {}, "options": [{"value": "all", "label": "All"}, {"value": "fav", "label": "Favourites"}]},
        {"type": "list", "max_height": 240, "title": "", "items": [
          {"title": "Sencha", "detail": "Green · 2 min", "symbol": "leaf", "selected": true, "mark": "pin.fill", "mark_label": "Favourite", "press": {"label": "Sencha", "go": {"set": {"t": "sencha"}}}},
          {"title": "Assam", "detail": "Black · 4 min", "color": "#8A4B2A", "press": {"label": "Assam", "go": {"set": {"t": "assam"}}}}]}]},
      {"joined": true, "row": "shelf", "weight": 59, "blocks": [{"type": "preview", "kind": "Green", "kind_symbol": "leaf", "title": "Sencha", "text": "Steep at 75 °C.\nTwo infusions.", "footer": "Bought in March",
        "actions": [{"type": "button", "label": "Forget", "tool": "forget", "symbol": "trash", "shape": "icon"}, {"type": "button", "label": "Brew", "tool": "brew", "style": "accent", "symbol": "play.fill"}]}]},
      {"title": "Sound", "card": true, "row": "more", "weight": 1, "blocks": [{"type": "choice", "style": "bar", "label": "Play on", "selected": "b", "tool": "s", "input": {}, "options": [{"value": "a", "label": "Mac"}, {"value": "b", "label": "Both", "symbol": "speaker"}]},
        {"type": "heading", "title": "Reminders", "rule": true}, {"type": "note", "text": "Your microphone is never used.", "style": "plain", "symbol": "mic.slash"}]},
      {"title": "Ask", "card": true, "row": "more", "weight": 1, "blocks": [{"type": "ask", "label": "What's a good evening tea?", "ask": "What's a good evening tea?", "row": true}, {"type": "note", "text": "Tea looks good.", "style": "verdict", "tone": "good", "symbol": "checkmark"}]},
      {"title": "Heads-ups", "card": true, "blocks": [{"type": "heads_ups", "show": ["done"], "more": "All of them", "less": "Fewer"}]}
     ]}
    """#

    @MainActor static func model() -> ExtensionPageModel {
        let info = ExtensionPageInfo(extensionId: "dev.example.tea", extensionName: "Tea Timer", page: "tea", title: "Tea Timer")
        let page = (try? JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))).flatMap { try? ExtensionPage.parse($0) } ?? ExtensionPage()
        let alert = { (name: String, title: String) in
            ExtensionPageModel.Alert(kind: ExtensionWatcherKind(extensionId: info.extensionId, watcher: name, title: title, description: "Tells you when it happens.", config: [:]), watcherId: nil)
        }
        return ExtensionPageModel(info: info, page: page, history: [:], alerts: [alert("done", "A brew is done"), alert("hot", "Water too hot")], updated: Date())
    }
}
#endif
