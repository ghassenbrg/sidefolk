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
        case "dev.sidefolk.calculator": String(localized: "Calculator", comment: "A built-in extension: sums, units and dates")
        case "dev.sidefolk.currency": String(localized: "Currency", comment: "A built-in extension: exchange rates")
        case "dev.sidefolk.playtime": String(localized: "Playtime", comment: "A built-in extension: dice, coins and a trivia quiz")
        case "dev.sidefolk.images": String(localized: "Images", comment: "A built-in extension: photo details and converted copies")
        case "dev.sidefolk.pdf": String(localized: "PDF Tools", comment: "A built-in extension")
        case "dev.sidefolk.qr-codes": String(localized: "QR Codes", comment: "A built-in extension")
        case "dev.sidefolk.archives": String(localized: "Archives", comment: "A built-in extension: zip files")
        case "dev.sidefolk.dev-toolbox": String(localized: "Dev Toolbox", comment: "A built-in extension for software developers")
        case "dev.sidefolk.feeds": String(localized: "Feeds", comment: "A built-in extension: RSS and Atom feeds")
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
        case "dev.sidefolk.calculator":
            String(localized: "Sums, percentages, unit conversions and date maths worked out exactly, so an answer never rests on a guess.")
        case "dev.sidefolk.currency":
            String(localized: "Converts money between the euro and 30 major currencies with the European Central Bank's daily reference rates, and tells you when a rate crosses a line. Nothing about you is sent.")
        case "dev.sidefolk.playtime":
            String(localized: "A break with your companion: flip a coin, roll dice, let chance pick, play rock, paper, scissors, or a trivia quiz that keeps your score.")
        case "dev.sidefolk.images":
            String(localized: "A photo's details, and copies of pictures converted to JPEG, PNG or HEIC, made smaller, or without their location. Your originals stay as they are.")
        case "dev.sidefolk.pdf":
            String(localized: "A PDF's details and text, several PDFs combined into one, and some of their pages saved as a new PDF. Your originals stay as they are.")
        case "dev.sidefolk.qr-codes":
            String(localized: "Makes a QR code picture of a link or text, and reads the QR code in a picture or a screenshot.")
        case "dev.sidefolk.archives":
            String(localized: "Zips files and folders so you can send them, and opens zip files you receive, with macOS's own tools.")
        case "dev.sidefolk.dev-toolbox":
            String(localized: "For developers: format JSON, encode and decode base64, URLs and hex, decode JWTs, convert timestamps, make UUIDs, and check a file's checksum.")
        case "dev.sidefolk.feeds":
            String(localized: "The latest posts of blogs, news sites and podcasts from their RSS or Atom feeds, and a heads-up when a new one appears.")
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
        case ("dev.sidefolk.system-vitals", "about"): String(localized: "About this Mac")
        case ("dev.sidefolk.weather", "forecast"): String(localized: "Weather forecast")
        case ("dev.sidefolk.weather", "sun_and_moon"): String(localized: "Sunrise, sunset and the moon")
        case ("dev.sidefolk.calculator", "calculate"): String(localized: "Calculate")
        case ("dev.sidefolk.calculator", "convert_units"): String(localized: "Convert units")
        case ("dev.sidefolk.calculator", "date_math"): String(localized: "Date maths")
        case ("dev.sidefolk.currency", "convert_currency"): String(localized: "Convert money")
        case ("dev.sidefolk.playtime", "chance"): String(localized: "Coin, dice and random picks")
        case ("dev.sidefolk.playtime", "trivia"): String(localized: "Trivia quiz")
        case ("dev.sidefolk.playtime", "rock_paper_scissors"): String(localized: "Rock, paper, scissors")
        case ("dev.sidefolk.images", "image_info"): String(localized: "Picture details")
        case ("dev.sidefolk.images", "convert_images"): String(localized: "Convert pictures")
        case ("dev.sidefolk.pdf", "pdf_info"): String(localized: "PDF details")
        case ("dev.sidefolk.pdf", "pdf_text"): String(localized: "Read a PDF's text")
        case ("dev.sidefolk.pdf", "combine_pdfs"): String(localized: "Combine PDFs")
        case ("dev.sidefolk.pdf", "extract_pages"): String(localized: "Take pages out of a PDF")
        case ("dev.sidefolk.qr-codes", "make_qr"): String(localized: "Make a QR code")
        case ("dev.sidefolk.qr-codes", "read_qr"): String(localized: "Read a QR code")
        case ("dev.sidefolk.archives", "zip"): String(localized: "Make a zip file")
        case ("dev.sidefolk.archives", "unzip"): String(localized: "Open a zip file")
        case ("dev.sidefolk.dev-toolbox", "transform"): String(localized: "Transform text")
        case ("dev.sidefolk.dev-toolbox", "timestamp"): String(localized: "Convert a timestamp")
        case ("dev.sidefolk.dev-toolbox", "generate"): String(localized: "Generate IDs")
        case ("dev.sidefolk.dev-toolbox", "checksum"): String(localized: "File checksum")
        case ("dev.sidefolk.feeds", "read_feed"): String(localized: "Latest posts")
        default: nil
        }
    }

    static func watcher(_ id: String, _ watcher: String) -> String? {
        switch (id, watcher) {
        case ("dev.sidefolk.system-vitals", "battery_low"): String(localized: "Battery low")
        case ("dev.sidefolk.system-vitals", "disk_low"): String(localized: "Disk space low")
        case ("dev.sidefolk.weather", "rain_soon"): String(localized: "Rain soon")
        case ("dev.sidefolk.currency", "rate_crosses"): String(localized: "Exchange rate")
        case ("dev.sidefolk.feeds", "new_post"): String(localized: "New post")
        default: nil
        }
    }
}
