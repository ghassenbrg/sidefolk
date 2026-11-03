#if DEBUG
import Foundation
import SidefolkCore

/// Pages a program drew, from `$SIDEFOLK_SNAPSHOT_PAGES/*.json` (`{"title", "icon", "width", "folder", "alerts": [{"watcher", "title", "description", "on"}], "page": {…}}`): how
/// an extension checks what it draws in every state, without the state. Past readings are made up from each chart's value now.
struct SamplePageFiles {
    var name: String
    var width: CGFloat
    private var json: JSONValue

    static func load() -> [SamplePageFiles] {
        guard let path = ProcessInfo.processInfo.environment["SIDEFOLK_SNAPSHOT_PAGES"],
              let names = try? FileManager.default.contentsOfDirectory(atPath: path) else { return [] }
        return names.sorted().filter { $0.hasSuffix(".json") }.compactMap { name in
            guard let data = FileManager.default.contents(atPath: path + "/" + name), let json = try? JSONDecoder().decode(JSONValue.self, from: data) else { return nil }
            return SamplePageFiles(name: String(name.dropLast(5)), width: CGFloat(json["width"]?.doubleValue ?? 1100), json: json)
        }
    }

    @MainActor func model() -> ExtensionPageModel {
        let title = json["title"]?.stringValue ?? name
        let info = ExtensionPageInfo(extensionId: "dev.example.\(name)", extensionName: title, page: name, title: title, iconPath: json["icon"]?.stringValue)
        guard let page = json["page"].flatMap({ try? ExtensionPage.parse($0) }) else { return ExtensionPageModel(info: info, problem: "That isn't a page.") }
        let now = Date()
        var history: [String: [ExtensionPageHistory.Point]] = [:]
        // Nothing past the top of a chart that has one.
        var tops: [String: Double] = [:]
        for section in page.sections {
            for case .chart(let chart) in section.blocks { for series in chart.series { tops["\(chart.id)/\(series.key)"] = chart.max } }
        }
        for (key, value) in page.samples {
            history[key] = (0..<60).map { i in
                ExtensionPageHistory.Point(now.addingTimeInterval(Double(i - 60) * 10), min(tops[key] ?? .infinity, max(0, value * (1 + 0.28 * sin(Double(i) / 6) + 0.1 * sin(Double(i) * 0.9)))))
            }
        }
        let alerts = (json["alerts"]?.arrayValue ?? []).map { a in
            ExtensionPageModel.Alert(kind: ExtensionWatcherKind(extensionId: info.extensionId, watcher: a["watcher"]?.stringValue ?? "",
                                                                title: a["title"]?.stringValue ?? "", description: a["description"]?.stringValue ?? "", config: [:]),
                                     watcherId: a["on"]?.boolValue == true ? "on" : nil)
        }
        return ExtensionPageModel(info: info, page: page, history: history, alerts: alerts, updated: now, folder: json["folder"]?.stringValue.map { URL(fileURLWithPath: $0, isDirectory: true) })
    }
}
#endif
