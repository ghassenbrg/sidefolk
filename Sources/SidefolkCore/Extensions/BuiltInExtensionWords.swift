import Foundation

/// The built-in extensions' words in the person's language (D28, D39). Their manifests are English
/// files in `extensions/`; the app ships them, so their names, descriptions and titles come from the
/// string catalog instead. Only the app's own copies use this (`origin == .bundled`): anyone else's
/// extension, a hand-installed copy under the same id included, shows its own text.
enum BuiltInExtensionWords {
    static func name(_ id: String) -> String? {
        switch id {
        case "dev.sidefolk.git": "Git"
        case "dev.sidefolk.world-clock": String(localized: "World Clock", comment: "A built-in extension: the time in other places")
        case "dev.sidefolk.system-vitals": String(localized: "System Vitals", comment: "A built-in extension: battery, disk and memory")
        case "dev.sidefolk.weather": String(localized: "Weather", comment: "A built-in extension: forecasts from Open-Meteo")
        default: nil
        }
    }

    static func description(_ id: String) -> String? {
        switch id {
        case "dev.sidefolk.git":
            String(localized: "Clone public repositories into a folder you choose, and check, update and read the history of the ones you have.")
        case "dev.sidefolk.world-clock":
            String(localized: "The time anywhere in the world, and a time converted between places, with daylight saving worked out exactly.")
        case "dev.sidefolk.system-vitals":
            String(localized: "Battery, disk and memory at a glance, and a nudge when the battery or the disk runs low.")
        case "dev.sidefolk.weather":
            String(localized: "Today's weather and the week ahead for any place, and a heads-up before rain, from Open-Meteo. Only the place you ask about leaves your Mac.")
        default: nil
        }
    }

    static func tool(_ id: String, _ tool: String) -> String? {
        switch (id, tool) {
        case ("dev.sidefolk.git", "clone"): String(localized: "Clone a repository")
        case ("dev.sidefolk.git", "status"): String(localized: "Repository status")
        case ("dev.sidefolk.git", "pull"): String(localized: "Pull the latest changes")
        case ("dev.sidefolk.git", "log"): String(localized: "Recent commits")
        case ("dev.sidefolk.world-clock", "current_time"): String(localized: "Time around the world")
        case ("dev.sidefolk.world-clock", "convert_time"): String(localized: "Convert a time between places")
        case ("dev.sidefolk.system-vitals", "battery"): String(localized: "Battery status")
        case ("dev.sidefolk.system-vitals", "disk"): String(localized: "Disk space")
        case ("dev.sidefolk.system-vitals", "memory"): String(localized: "Memory use", comment: "The Mac's memory (RAM) in use")
        case ("dev.sidefolk.weather", "forecast"): String(localized: "Weather forecast")
        default: nil
        }
    }

    static func watcher(_ id: String, _ watcher: String) -> String? {
        switch (id, watcher) {
        case ("dev.sidefolk.system-vitals", "battery_low"): String(localized: "Battery low")
        case ("dev.sidefolk.system-vitals", "disk_low"): String(localized: "Disk space low")
        case ("dev.sidefolk.weather", "rain_soon"): String(localized: "Rain soon")
        default: nil
        }
    }
}
