#if DEBUG
import AppKit

/// Dev (`swift scripts/dev.swift ax`): the accessibility tree of every visible window, as VoiceOver walks it (role,
/// label, value, whether it can be pressed), written beside the snapshots. Read from inside the app, so it needs no
/// Accessibility permission for the tool asking (D84's VoiceOver pass).
@MainActor
enum AccessibilityDump {
    static func write(to folder: URL) {
        var lines: [String] = []
        // Asking for this app's own tree is what makes SwiftUI build it: it builds only for an assistive app. The calls
        // themselves are refused (this tool isn't trusted), and that's enough. It takes a moment to appear.
        let app = AXUIElementCreateApplication(getpid())
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        RunLoop.main.run(until: Date().addingTimeInterval(2))
        for window in NSApp.windows where window.isVisible {
            lines.append("=== \(type(of: window)) \(Int(window.frame.minX)),\(Int(window.frame.minY)) \(Int(window.frame.width))×\(Int(window.frame.height))")
            walk(window, depth: 1, into: &lines)
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("ax-\(Int(Date().timeIntervalSince1970)).txt")
        try? lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
    }

    private static func walk(_ element: Any, depth: Int, into lines: inout [String]) {
        guard depth < 30, let node = element as? NSAccessibilityProtocol else { return }
        let ignored = node.isAccessibilityElement() == false
        let role = node.accessibilityRole()?.rawValue ?? "?"
        let children = node.accessibilityChildren() ?? []
        // Containers VoiceOver skips are left out, their children kept, so the tree reads as it is heard.
        if !ignored || role == "AXWindow" {
            var parts = [role]
            if let sub = node.accessibilitySubrole()?.rawValue { parts[0] += "/" + sub }
            if let label = node.accessibilityLabel(), !label.isEmpty { parts.append("label=\"\(label.oneLine)\"") }
            if let title = node.accessibilityTitle(), !title.isEmpty { parts.append("title=\"\(title.oneLine)\"") }
            if let value = node.accessibilityValue() { let v = "\(value)".oneLine; if !v.isEmpty { parts.append("value=\"\(v)\"") } }
            if let help = node.accessibilityHelp(), !help.isEmpty { parts.append("help=\"\(help.oneLine)\"") }
            if let ph = node.accessibilityPlaceholderValue(), !ph.isEmpty { parts.append("placeholder=\"\(ph.oneLine)\"") }
            if node.isAccessibilitySelected() == true { parts.append("[selected]") }
            lines.append(String(repeating: "  ", count: depth) + parts.joined(separator: " "))
        }
        for child in children { walk(child, depth: ignored ? depth : depth + 1, into: &lines) }
    }
}

private extension String {
    var oneLine: String { replacingOccurrences(of: "\n", with: " ").prefix(100).description }
}
#endif
