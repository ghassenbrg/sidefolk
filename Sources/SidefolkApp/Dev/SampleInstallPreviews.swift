#if DEBUG
import Foundation
import SidefolkCore

/// Install previews for the snapshots, one per kind of source (D71), each built from real permissions by the same
/// code the app uses, so the sheet's words in a snapshot are the ones a person would read.
extension FixtureServices {
    private static let home = FolderAccess.canonical(NSHomeDirectory()) ?? NSHomeDirectory()

    /// A folder from somewhere: network and a fixed folder, the strong warning.
    static let samplePreview = ExtensionInstallPreview(
        id: "dev.example.trip-planner", name: "Trip Planner", version: "1.2.0",
        description: "Day plans and packing lists from the trips in your Travel folder.",
        sourceFolder: URL(fileURLWithPath: NSHomeDirectory() + "/Downloads/trip-planner"),
        review: InstallReview(id: "dev.example.trip-planner", permissions: ExtensionPermissions(network: true, read: [home + "/Documents/Travel"]),
                              background: false, toolRisks: [.medium, .medium], update: nil, source: .folder),
        toolNames: ["plan_day", "packing_list"], watcherNames: [], folk: "scout",
        services: [.init(name: "Open Trips", hosts: ["api.opentrips.example.com"])])

    /// Sidefolk's own from the gallery, naming the service it talks to (D98): the sheet takes its word.
    static let servicePreview = ExtensionInstallPreview(
        id: SampleAddons.skyWatch, name: "Sky Watch", version: "1.3.0-snapshot.1",
        description: "Today's weather and the week ahead for any place, and a heads-up before rain, from Open-Meteo. Only the place you ask about leaves your Mac.",
        sourceFolder: URL(fileURLWithPath: "/tmp/Addons/Downloads/sky-watch"),
        review: InstallReview(id: SampleAddons.skyWatch, permissions: ExtensionPermissions(network: true), background: false,
                              toolRisks: [.medium, .medium], update: nil, source: .gallery),
        toolNames: ["Weather forecast", "Sunrise, sunset and the moon"], watcherNames: ["Rain soon"], folk: "scout",
        services: [.init(name: "Open-Meteo", hosts: ["api.open-meteo.com", "geocoding-api.open-meteo.com"])])

    /// Cast Along's permissions from someone else's folder: the same facts as the gallery's, said as a warning.
    static let unknownMirrorPreview = ExtensionInstallPreview(
        id: "com.example.screen-share", name: "Screen Share", version: "0.3.0",
        description: "Shows your screen on a TV in the same room.",
        sourceFolder: URL(fileURLWithPath: NSHomeDirectory() + "/Downloads/screen-share"),
        review: InstallReview(id: "com.example.screen-share", permissions: mirrorPermissions, background: true,
                              toolRisks: [.medium, .medium, .medium], update: nil, source: .folder),
        toolNames: ["Share screen", "Play a file", "Stop"], watcherNames: [])

    /// Sidefolk's own Cast Along from the gallery (D69): the founder's case, calm and complete.
    static let galleryPreview = ExtensionInstallPreview(
        id: SampleAddons.castAlong, name: "Cast Along", version: "1.0.0-snapshot.1",
        description: "Shows your Mac's screen, one window or part of it, with its sound, on an Android TV running a companion app, "
            + "over an encrypted direct connection on your network, or plays a video file or link on the TV.",
        sourceFolder: URL(fileURLWithPath: "/tmp/Addons/Downloads/cast-along"),
        review: InstallReview(id: SampleAddons.castAlong, permissions: mirrorPermissions, background: true,
                              toolRisks: Array(repeating: .medium, count: 15), update: nil, source: .gallery),
        toolNames: ["TVs around", "Share screen to TV", "Play on TV", "Stop sharing", "Pair with a TV"],
        watcherNames: ["A paired TV is on", "Sharing to the TV ended"], commands: ["mirror my screen", "stop sharing"],
        pageNames: ["Cast Along"], folk: "byte")

    /// An official update that asks for more: shown prominently even though Sidefolk signed it.
    static let updatePreview = ExtensionInstallPreview(
        id: SampleAddons.codeMaker, name: "Code Maker", version: "1.1.0",
        description: "Makes QR codes and reads them from pictures.",
        sourceFolder: URL(fileURLWithPath: "/tmp/Addons/Downloads/code-maker"),
        review: {
            var review = InstallReview(id: SampleAddons.codeMaker, permissions: ExtensionPermissions(folders: .read, media: true), background: false,
                                       toolRisks: [.low, .medium], update: nil, source: .gallery)
            review.update = .init(line: String(localized: "Updates \("1.0.0") to \("1.1.0").", comment: "Two version numbers"),
                                  added: [String(localized: "Can read a folder you name, for that request only")], removed: [])
            return review
        }(),
        toolNames: ["Make a QR code", "Read a QR code"], watcherNames: [])

    /// A draft Sidefolk's AI wrote, handed over for review (D39): the one waiting in Drafts. Extensions can't
    /// hold secrets, so the samples are things that need no account.
    static let draftPreview = ExtensionInstallPreview(
        id: "local.pomodoro-log", name: "Pomodoro Log", version: "0.1.0",
        description: "Logs your focus sessions in its own folder and adds them up by day.",
        sourceFolder: URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/Sidefolk/ExtensionDrafts/local.pomodoro-log"),
        review: InstallReview(id: "local.pomodoro-log", permissions: ExtensionPermissions(), background: false,
                              toolRisks: [.low, .low], update: nil, source: .draft),
        toolNames: ["Start a session", "Today's sessions"], watcherNames: [])

    private static let mirrorPermissions = ExtensionPermissions(
        network: true, folders: .read, media: true, screen: true, udp: true,
        networkPurpose: "to find TVs on your local network and stream to them")
}
#endif
