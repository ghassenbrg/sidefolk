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
        case "dev.sidefolk.playtime": String(localized: "Playtime", comment: "A built-in extension: a trivia quiz and random picks")
        case "dev.sidefolk.images": String(localized: "Images", comment: "A built-in extension: photo details and converted copies")
        case "dev.sidefolk.pdf": String(localized: "PDF Tools", comment: "A built-in extension")
        case "dev.sidefolk.qr-codes": String(localized: "QR Codes", comment: "A built-in extension")
        case "dev.sidefolk.archives": String(localized: "Archives", comment: "A built-in extension: zip files")
        case "dev.sidefolk.dev-toolbox": String(localized: "Dev Toolbox", comment: "A built-in extension for software developers")
        case "dev.sidefolk.feeds": String(localized: "Feeds", comment: "A built-in extension: RSS and Atom feeds")
        case "dev.sidefolk.system-vitals-plus": String(localized: "System Vitals+", comment: "A built-in extension: the whole Mac with live charts")
        case "dev.sidefolk.clipboard": String(localized: "Clipboard", comment: "A built-in extension: everything you copy")
        case "dev.sidefolk.keep-awake": String(localized: "Keep Awake", comment: "A built-in extension: keeps the Mac awake")
        case "dev.sidefolk.miraya": "Miraya"
        default: nil
        }
    }

    /// One line under the name in Settings; the description is under Details.
    static func tagline(_ id: String) -> String? {
        switch id {
        case "dev.sidefolk.git": String(localized: "Clone, update and check your repositories", comment: "Git: one line under its name")
        case "dev.sidefolk.world-clock": String(localized: "The time anywhere, and times between places", comment: "World Clock: one line under its name")
        case "dev.sidefolk.system-vitals": String(localized: "Battery, disk and memory at a glance", comment: "System Vitals: one line under its name")
        case "dev.sidefolk.weather": String(localized: "Today's weather and the week ahead", comment: "Weather: one line under its name")
        case "dev.sidefolk.calculator": String(localized: "Exact sums, units and dates", comment: "Calculator: one line under its name")
        case "dev.sidefolk.currency": String(localized: "Money in 30 currencies at today's rates", comment: "Currency: one line under its name")
        case "dev.sidefolk.playtime": String(localized: "Trivia and random picks for a break", comment: "Playtime: one line under its name")
        case "dev.sidefolk.images": String(localized: "Photo details and converted copies", comment: "Images: one line under its name")
        case "dev.sidefolk.pdf": String(localized: "Read, combine and split PDFs", comment: "PDF Tools: one line under its name")
        case "dev.sidefolk.qr-codes": String(localized: "Make and read QR codes", comment: "QR Codes: one line under its name")
        case "dev.sidefolk.archives": String(localized: "Zip and unzip files", comment: "Archives: one line under its name")
        case "dev.sidefolk.dev-toolbox": String(localized: "JSON, base64, JWTs, UUIDs and more", comment: "Dev Toolbox: one line under its name")
        case "dev.sidefolk.feeds": String(localized: "New posts from blogs, news and podcasts", comment: "Feeds: one line under its name")
        case "dev.sidefolk.system-vitals-plus": String(localized: "Your whole Mac at a glance, with live charts", comment: "System Vitals+: one line under its name")
        case "dev.sidefolk.clipboard": String(localized: "Everything you copy, a shortcut away", comment: "Clipboard: one line under its name")
        case "dev.sidefolk.keep-awake": String(localized: "Your Mac awake and you active, for as long as you say", comment: "Keep Awake: one line under its name")
        case "dev.sidefolk.miraya": String(localized: "Your Mac's screen and videos on your Android TV", comment: "Miraya: one line under its name")
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
            String(localized: "A break with your companion: a trivia quiz that keeps your score, and chance to pick a number or choose from a list.")
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
        case "dev.sidefolk.system-vitals-plus":
            String(localized: "The whole Mac in plain words: processor, graphics, memory, apps, disks, battery health, heat and network, as a page with live charts, a tile on Today, instant answers and a heads-up when something needs you. Nothing leaves your Mac.")
        case "dev.sidefolk.clipboard":
            String(localized: "Everything you copy, a shortcut away from any app: text with its formatting, links, pictures, files and code, searchable and pinnable. Copies from password managers are never kept; keys and card numbers are hidden and forgotten in two minutes. Nothing leaves your Mac.")
        case "dev.sidefolk.keep-awake":
            String(localized: "Keeps your Mac awake, and chat apps from marking you away, for as long as you say, until a time, while an app like Zoom is open, or until you stop it. Nothing moves on screen, and it lets go on battery or when the battery runs low.")
        case "dev.sidefolk.feeds":
            String(localized: "The latest posts of blogs, news sites and podcasts from their RSS or Atom feeds, and a heads-up when a new one appears.")
        case "dev.sidefolk.miraya":
            String(localized: "Shows your Mac's screen, one window or part of it, with its sound, on an Android TV running the Miraya app, over an encrypted direct connection on your network, or plays a video file or link on the TV. The first time, you compare a six-digit code on both screens. No account, no cloud.")
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
        case ("dev.sidefolk.playtime", "pick"): String(localized: "Random picks")
        case ("dev.sidefolk.playtime", "trivia"): String(localized: "Trivia quiz")
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
        case ("dev.sidefolk.system-vitals-plus", "health"): String(localized: "Mac health check")
        case ("dev.sidefolk.system-vitals-plus", "cpu"): String(localized: "Processor and graphics")
        case ("dev.sidefolk.system-vitals-plus", "memory"): String(localized: "Memory in detail")
        case ("dev.sidefolk.system-vitals-plus", "storage"): String(localized: "Storage")
        case ("dev.sidefolk.system-vitals-plus", "battery"): String(localized: "Battery in detail")
        case ("dev.sidefolk.system-vitals-plus", "network"): String(localized: "Network activity")
        case ("dev.sidefolk.system-vitals-plus", "top_apps"): String(localized: "What's using the Mac")
        case ("dev.sidefolk.system-vitals-plus", "specs"): String(localized: "This Mac's specs")
        case ("dev.sidefolk.clipboard", "recent_copies"): String(localized: "Recent copies")
        case ("dev.sidefolk.clipboard", "search_copies"): String(localized: "Search copies")
        case ("dev.sidefolk.clipboard", "copy_again"): String(localized: "Copy again")
        case ("dev.sidefolk.clipboard", "pause"): String(localized: "Pause the history")
        case ("dev.sidefolk.clipboard", "resume"): String(localized: "Resume the history")
        case ("dev.sidefolk.clipboard", "clear_history"): String(localized: "Clear the history")
        case ("dev.sidefolk.clipboard", "set_option"): String(localized: "Clipboard setting")
        case ("dev.sidefolk.keep-awake", "keep_awake"): String(localized: "Keep the Mac awake")
        case ("dev.sidefolk.keep-awake", "stop_keeping_awake"): String(localized: "Let the Mac sleep")
        case ("dev.sidefolk.keep-awake", "awake_status"): String(localized: "Keep Awake status")
        case ("dev.sidefolk.keep-awake", "extend"): String(localized: "Keep awake longer")
        case ("dev.sidefolk.keep-awake", "set_option"): String(localized: "Keep Awake setting")
        case ("dev.sidefolk.miraya", "find_tvs"): String(localized: "TVs around")
        case ("dev.sidefolk.miraya", "share_screen"): String(localized: "Share screen to TV")
        case ("dev.sidefolk.miraya", "play_on_tv"): String(localized: "Play on TV")
        case ("dev.sidefolk.miraya", "stop"): String(localized: "Stop sharing")
        case ("dev.sidefolk.miraya", "pause"): String(localized: "Pause sharing")
        case ("dev.sidefolk.miraya", "resume"): String(localized: "Resume sharing")
        case ("dev.sidefolk.miraya", "seek"): String(localized: "Skip in the video")
        case ("dev.sidefolk.miraya", "tv_volume"): String(localized: "TV volume")
        case ("dev.sidefolk.miraya", "pair_tv"): String(localized: "Pair with a TV")
        case ("dev.sidefolk.miraya", "confirm_pairing"): String(localized: "Codes match · Pair")
        case ("dev.sidefolk.miraya", "forget_tv"): String(localized: "Forget a TV")
        case ("dev.sidefolk.miraya", "choose_tv"): String(localized: "Choose a TV")
        case ("dev.sidefolk.miraya", "list_windows"): String(localized: "Windows to share")
        case ("dev.sidefolk.miraya", "set_option"): String(localized: "Miraya setting")
        case ("dev.sidefolk.miraya", "tv_status"): String(localized: "What's on the TV")
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
        case ("dev.sidefolk.system-vitals-plus", "cpu_busy"): String(localized: "Mac working hard")
        case ("dev.sidefolk.system-vitals-plus", "app_hog"): String(localized: "An app using a lot")
        case ("dev.sidefolk.system-vitals-plus", "memory_pressure"): String(localized: "Memory tight")
        case ("dev.sidefolk.system-vitals-plus", "hot"): String(localized: "Mac running hot")
        case ("dev.sidefolk.system-vitals-plus", "disk_low"): String(localized: "Disk space low")
        case ("dev.sidefolk.system-vitals-plus", "battery_low"): String(localized: "Battery low")
        case ("dev.sidefolk.system-vitals-plus", "battery_health"): String(localized: "Battery worn")
        case ("dev.sidefolk.keep-awake", "ended"): String(localized: "Keep Awake ended")
        case ("dev.sidefolk.miraya", "tv_on"): String(localized: "A paired TV is on")
        case ("dev.sidefolk.miraya", "ended"): String(localized: "Sharing to the TV ended")
        default: nil
        }
    }

    /// A page's title in the sidebar (D62).
    static func page(_ id: String, _ page: String) -> String? {
        switch (id, page) {
        case ("dev.sidefolk.system-vitals-plus", "mac"): String(localized: "Your Mac", comment: "System Vitals+: its page in Home's sidebar")
        case ("dev.sidefolk.clipboard", "clipboard"): String(localized: "Clipboard", comment: "Clipboard: its page in Home's sidebar")
        case ("dev.sidefolk.keep-awake", "awake"): String(localized: "Keep Awake", comment: "Keep Awake: its page in Home's sidebar")
        case ("dev.sidefolk.miraya", "miraya"): "Miraya"
        default: nil
        }
    }

    /// A palette's title (D63).
    static func palette(_ id: String, _ palette: String) -> String? {
        switch (id, palette) {
        case ("dev.sidefolk.clipboard", "history"): String(localized: "Clipboard", comment: "Clipboard: the title of its pop-up list")
        default: nil
        }
    }

    static func placeholder(_ id: String, _ palette: String) -> String? {
        switch (id, palette) {
        case ("dev.sidefolk.clipboard", "history"): String(localized: "Search what you copied", comment: "Clipboard: the search field's hint")
        default: nil
        }
    }
}
