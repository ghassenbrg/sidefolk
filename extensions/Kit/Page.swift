import Foundation

/// A page the extension adds to Home (docs/EXTENSIONS.md › Pages). It says what is true; Sidefolk draws it with its
/// own parts, keeps the past of every chart, and refreshes it as often as the manifest says.
///
/// ```swift
/// ext.page("mac") { args in
///     Page(summary: Summary("All good", detail: "CPU 12%", tone: .good),
///          sections: [Section("Right now", [.gauge("CPU", "12%", fraction: 0.12, tone: .good)])])
/// }
/// ```
public struct Page {
    public var summary: Summary?
    public var sections: [Section]

    public init(summary: Summary? = nil, sections: [Section] = []) {
        self.summary = summary
        self.sections = sections
    }

    var json: [String: Any] {
        var out: [String: Any] = ["sections": sections.filter { !$0.blocks.isEmpty }.map(\.json)]
        if let summary { out["summary"] = summary.json }
        return out
    }
}

public enum Tone: String {
    case good, warn, bad, info, neutral
}

/// The page in one line: on top of the page, and the Today tile when the manifest asks for one.
public struct Summary {
    public var title: String
    public var detail: String
    public var tone: Tone
    public var symbol: String?

    public init(_ title: String, detail: String = "", tone: Tone = .neutral, symbol: String? = nil) {
        self.title = title
        self.detail = detail
        self.tone = tone
        self.symbol = symbol
    }

    var json: [String: Any] {
        var out: [String: Any] = ["title": title, "detail": detail, "tone": tone.rawValue]
        if let symbol { out["symbol"] = symbol }
        return out
    }
}

public struct Section {
    public var title: String?
    public var blocks: [Block]

    public init(_ title: String? = nil, _ blocks: [Block]) {
        self.title = title
        self.blocks = blocks
    }

    var json: [String: Any] {
        var out: [String: Any] = ["blocks": blocks.map(\.json)]
        if let title { out["title"] = title }
        return out
    }
}

/// One line of a chart: its value now. Sidefolk remembers the earlier ones.
public struct Series {
    public var key: String
    public var label: String
    public var value: Double
    public var display: String?

    public init(_ key: String, _ label: String, _ value: Double, display: String? = nil) {
        self.key = key
        self.label = label
        self.value = value
        self.display = display
    }
}

public struct Bar {
    public var label: String
    public var value: String
    public var fraction: Double
    public var tone: Tone

    public init(_ label: String, _ value: String, fraction: Double, tone: Tone = .neutral) {
        self.label = label
        self.value = value
        self.fraction = fraction
        self.tone = tone
    }
}

public enum Block {
    /// A ring filled to `fraction` (0–1) with the value inside.
    case gauge(_ label: String, _ value: String, fraction: Double, tone: Tone = .neutral, caption: String? = nil)
    case stat(_ label: String, _ value: String, tone: Tone = .neutral, caption: String? = nil)
    /// `id` names the chart's history; `max` is the axis's top (nil scales to the data).
    case chart(id: String, _ title: String, unit: String? = nil, max: Double? = nil, caption: String? = nil, series: [Series])
    case bars(_ title: String, caption: String? = nil, _ items: [Bar])
    case facts(_ title: String? = nil, _ items: [(String, String)])
    case note(_ text: String, tone: Tone = .neutral)
    /// A button that asks Sidefolk this, as if typed in Ask.
    case ask(_ label: String, _ ask: String)

    var json: [String: Any] {
        switch self {
        case .gauge(let label, let value, let fraction, let tone, let caption):
            return Self.dropNil(["type": "gauge", "label": label, "value": value, "fraction": fraction, "tone": tone.rawValue, "caption": caption])
        case .stat(let label, let value, let tone, let caption):
            return Self.dropNil(["type": "stat", "label": label, "value": value, "tone": tone.rawValue, "caption": caption])
        case .chart(let id, let title, let unit, let max, let caption, let series):
            return Self.dropNil(["type": "chart", "id": id, "title": title, "unit": unit, "max": max, "caption": caption,
                                 "series": series.map { Self.dropNil(["key": $0.key, "label": $0.label, "value": $0.value, "display": $0.display]) }])
        case .bars(let title, let caption, let items):
            return Self.dropNil(["type": "bars", "title": title, "caption": caption,
                                 "items": items.map { ["label": $0.label, "value": $0.value, "fraction": $0.fraction, "tone": $0.tone.rawValue] }])
        case .facts(let title, let items):
            return Self.dropNil(["type": "facts", "title": title, "items": items.map { ["label": $0.0, "value": $0.1] }])
        case .note(let text, let tone):
            return ["type": "note", "text": text, "tone": tone.rawValue]
        case .ask(let label, let ask):
            return ["type": "ask", "label": label, "ask": ask]
        }
    }

    private static func dropNil(_ values: [String: Any?]) -> [String: Any] { values.compactMapValues { $0 } }
}
