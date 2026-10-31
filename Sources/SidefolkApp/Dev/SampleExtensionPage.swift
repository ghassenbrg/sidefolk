#if DEBUG
import Foundation
import SidefolkCore

/// System Vitals+'s page as it reads on a typical afternoon, with ten minutes of history: what the UI snapshots show
/// for extension pages (D62) without running the extension.
enum SampleExtensionPage {
    static let info = ExtensionPageInfo(extensionId: "dev.sidefolk.system-vitals-plus", extensionName: "System Vitals+", page: "mac",
                                        title: "Your Mac", symbol: "gauge.with.dots.needle.67percent", refresh: 3, history: true, widget: true)

    static let json = #"""
    {"summary": {"title": "Your Mac is doing fine", "detail": "CPU 18% · Memory 62% · 214 GB free · Battery 84%", "tone": "good", "symbol": "checkmark.seal.fill"},
     "sections": [
      {"title": "Right now", "blocks": [
        {"type": "gauge", "label": "CPU", "value": "18%", "fraction": 0.18, "tone": "good", "caption": "Most: Xcode"},
        {"type": "gauge", "label": "Memory", "value": "14.9 GB", "fraction": 0.62, "tone": "good", "caption": "of 24 GB"},
        {"type": "gauge", "label": "Disk", "value": "214 GB free", "fraction": 0.57, "tone": "good", "caption": "of 494 GB"},
        {"type": "gauge", "label": "Battery", "value": "84%", "fraction": 0.84, "tone": "good", "caption": "On battery, 6 h 40 min left"},
        {"type": "stat", "label": "Temperature", "value": "Cool", "tone": "good", "caption": "No slowing down"},
        {"type": "stat", "label": "Graphics", "value": "12%", "tone": "good", "caption": "GPU busy"},
        {"type": "stat", "label": "Network", "value": "↓ 1.4 MB/s", "caption": "↑ 86 KB/s"},
        {"type": "stat", "label": "On for", "value": "3 days 4 hours"}]},
      {"title": "Worth a look", "blocks": [
        {"type": "note", "tone": "info", "text": "Xcode has used the processor steadily for a while. It eases once its build finishes."}]},
      {"title": "Over time", "blocks": [
        {"type": "chart", "id": "cpu", "title": "Processor and graphics", "unit": "%", "max": 100,
         "caption": "How busy they were. Short peaks are normal; a long plateau means something is working hard.",
         "series": [{"key": "total", "label": "CPU", "value": 18, "display": "18%"}, {"key": "gpu", "label": "Graphics", "value": 12, "display": "12%"}]},
        {"type": "chart", "id": "memory", "title": "Memory used", "unit": "GB", "max": 24,
         "caption": "Cached files aren't counted: macOS gives that space back the moment an app needs it.",
         "series": [{"key": "used", "label": "Used", "value": 14.9, "display": "14.9 GB"}]},
        {"type": "chart", "id": "network", "title": "Network", "unit": "MB/s", "caption": "Everything this Mac downloads and uploads, every app together.",
         "series": [{"key": "down", "label": "Download", "value": 1.4, "display": "1.4 MB/s"}, {"key": "up", "label": "Upload", "value": 0.09, "display": "86 KB/s"}]},
        {"type": "chart", "id": "battery", "title": "Battery charge", "unit": "%", "max": 100,
         "series": [{"key": "charge", "label": "Charge", "value": 84, "display": "84%"}]}]},
      {"title": "What's using your Mac", "blocks": [
        {"type": "bars", "title": "Processor", "caption": "Share of the whole processor, by app.", "items": [
          {"label": "Xcode", "value": "9%", "fraction": 1, "tone": "good"}, {"label": "Safari", "value": "4%", "fraction": 0.44, "tone": "good"},
          {"label": "Music", "value": "2%", "fraction": 0.22, "tone": "good"}, {"label": "WindowServer", "value": "1%", "fraction": 0.11, "tone": "good"}]},
        {"type": "bars", "title": "Memory", "caption": "How much each app holds. Helpers and background parts count as their app.", "items": [
          {"label": "Xcode", "value": "4.1 GB", "fraction": 0.17}, {"label": "Safari", "value": "2.8 GB", "fraction": 0.12},
          {"label": "Photos", "value": "1.2 GB", "fraction": 0.05}, {"label": "Mail", "value": "640 MB", "fraction": 0.03}]}]},
      {"title": "Memory", "blocks": [
        {"type": "facts", "items": [{"label": "Apps", "value": "8.2 GB"}, {"label": "Kept by macOS", "value": "3.1 GB"},
          {"label": "Compressed", "value": "3.6 GB"}, {"label": "Cached files", "value": "5.9 GB, free to reuse"}, {"label": "Swap", "value": "None"},
          {"label": "Pressure", "value": "Normal: no strain"}]},
        {"type": "note", "tone": "good", "text": "A Mac uses spare memory to keep things quick, so it often looks nearly full. Memory pressure is what matters, and it's normal."}]},
      {"title": "Battery", "blocks": [
        {"type": "facts", "items": [{"label": "Charge", "value": "84%"}, {"label": "State", "value": "On battery, 6 h 40 min left"},
          {"label": "Health", "value": "96% of new · Normal"}, {"label": "Charge cycles", "value": "212"}]}]},
      {"title": "Ask about it", "blocks": [
        {"type": "ask", "label": "What's slowing my Mac?", "ask": "What's slowing my Mac?"},
        {"type": "ask", "label": "Should I restart?", "ask": "Should I restart my Mac?"},
        {"type": "ask", "label": "Is my battery healthy?", "ask": "Is my battery healthy?"}]}
     ]}
    """#

    @MainActor static func model(now: Date = Date()) -> ExtensionPageModel {
        let page = (try? JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))).flatMap { try? ExtensionPage.parse($0) } ?? ExtensionPage()
        // Ten minutes every three seconds, wandering smoothly around each value now.
        var history: [String: [ExtensionPageHistory.Point]] = [:]
        for (key, value) in page.samples {
            let seed = Double(key.unicodeScalars.reduce(0) { $0 + Int($1.value) })
            history[key] = (0..<200).map { i in
                let t = now.addingTimeInterval(-Double(199 - i) * 3)
                let wave = sin(Double(i) / 9 + seed) * 0.12 + sin(Double(i) / 23 + seed / 3) * 0.08
                return ExtensionPageHistory.Point(t, max(0, value * (1 + wave)))
            }
        }
        let alerts = [("cpu_busy", "Mac working hard", "Tells you when the processor stays very busy, and which app is behind it.", true),
                      ("memory_pressure", "Memory tight", "Tells you when macOS runs short of memory and apps may slow down.", true),
                      ("battery_health", "Battery worn", "Tells you when the battery's health drops below a level or it reports a fault.", false)]
            .map { name, title, description, on in
                ExtensionPageModel.Alert(kind: ExtensionWatcherKind(extensionId: info.extensionId, watcher: name, title: title, description: description, config: [:]),
                                         watcherId: on ? "w-\(name)" : nil)
            }
        return ExtensionPageModel(info: info, page: page, history: history, alerts: alerts, updated: now)
    }

    /// Keep Awake holding for an hour, with its switches (D63).
    @MainActor static func keepAwake(now: Date = Date()) -> ExtensionPageModel {
        let json = #"""
        {"summary": {"title": "Awake until 18:00", "detail": "1 h 25 min left · Screen on · showing you active (12× so far)", "tone": "good",
                     "symbol": "cup.and.saucer.fill", "control": {"type": "switch", "label": "Keep awake", "on": true, "tool": "keep_awake"}},
         "sections": [
          {"blocks": [{"type": "button", "label": "30 min more", "tool": "extend", "input": {"minutes": 30}, "symbol": "plus"},
                      {"type": "button", "label": "Stop", "tool": "stop_keeping_awake", "style": "destructive", "symbol": "stop.fill"}]},
          {"title": "How", "blocks": [
            {"type": "switch", "label": "Keep the screen on", "detail": "Off: the Mac stays awake (downloads, builds) and the screen may sleep.", "on": true, "tool": "set_option"},
            {"type": "switch", "label": "Keep me active in chat apps", "detail": "While you're away, Sidefolk moves the pointer by nothing about once a minute.", "on": true, "tool": "set_option"},
            {"type": "switch", "label": "Only while plugged in", "detail": "On battery it waits, and holds again when you plug in.", "on": false, "tool": "set_option"}]},
          {"title": "Ask for more", "blocks": [{"type": "ask", "label": "While Zoom is open", "ask": "Keep my Mac awake while Zoom is open"}]}
         ]}
        """#
        let page = (try? JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))).flatMap { try? ExtensionPage.parse($0) } ?? ExtensionPage()
        return ExtensionPageModel(info: awakeInfo, page: page, history: [:], alerts: [], updated: now)
    }

    /// Clipboard's palette with a few copies (D63).
    @MainActor static func palette(host: ExtensionHost) -> PaletteModel {
        let info = ExtensionPaletteInfo(extensionId: "dev.sidefolk.clipboard", extensionName: "Clipboard", palette: "history", title: "Clipboard",
                                        hotkey: "shift+cmd+c", placeholder: "Search what you copied")
        let items: [ExtensionPaletteList.Item] = [
            .init(id: "1", title: "Meeting notes: ship System Vitals+ on Friday", detail: "just now", kind: .text, pinned: false),
            .init(id: "2", title: "https://github.com/ghassenbrg/sidefolk/pull/2", detail: "3 min ago · copied 2×", kind: .link, pinned: true),
            .init(id: "3", title: "func hello() {", detail: "Xcode · 12 min ago · 3 lines", kind: .code),
            .init(id: "4", title: "•••••••• (looks like a password or key)", detail: "just now · forgotten in 2 min", kind: .text),
            .init(id: "5", title: "#2ED4D9", detail: "1 h ago", kind: .color),
            .init(id: "6", title: "Picture 1440 × 900", detail: "yesterday", kind: .image),
            .init(id: "7", title: "report.pdf, budget.xlsx", detail: "2 days ago", kind: .file),
        ]
        return PaletteModel(info: info, host: host, items: items, note: "312 copies kept")
    }

    static let awakeInfo = ExtensionPageInfo(extensionId: "dev.sidefolk.keep-awake", extensionName: "Keep Awake", page: "awake", title: "Keep Awake",
                                             symbol: "cup.and.saucer", refresh: 5, widget: true, needsAccessibility: true)

    /// Keep Awake's tile, its main switch on it (D67).
    static func awakeWidget() -> ExtensionWidget {
        let control = (try? ExtensionPage.parse(["summary": ["title": "x", "control": ["type": "switch", "label": "Keep awake", "on": true, "tool": "keep_awake"]]]))?
            .summary?.control
        return ExtensionWidget(info: awakeInfo, summary: ExtensionPage.Summary(title: "Awake until 18:00", detail: "1 h 25 min left · Screen on",
                                                                               tone: .good, symbol: "cup.and.saucer.fill", control: control), at: Date())
    }

    static func widget() -> ExtensionWidget {
        ExtensionWidget(info: info, summary: ExtensionPage.Summary(title: "Your Mac is doing fine", detail: "CPU 18% · Memory 62% · 214 GB free · Battery 84%",
                                                                    tone: .good, symbol: "checkmark.seal.fill"), at: Date())
    }
}
#endif
