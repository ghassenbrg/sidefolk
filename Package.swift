// swift-tools-version: 6.2
import PackageDescription

/// The extensions that ship with Sidefolk (extensions/catalog.json): one small program each, built with the app and
/// signed inside it, so they need nothing installed on the Mac (D39, amended 2026-10-27).
let builtInExtensions = [
    "git", "world-clock", "system-vitals", "weather", "calculator", "currency", "playtime", "images", "pdf", "qr-codes", "archives",
    "dev-toolbox", "feeds",
]

let package = Package(
    name: "Sidefolk",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "SidefolkApp", targets: ["SidefolkApp"]),
        .executable(name: "sidefolk", targets: ["sidefolk"]),
        .executable(name: "sidefolk-render", targets: ["sidefolk-render"]),
    ] + builtInExtensions.map { .executable(name: "ext-\($0)", targets: ["ext-\($0)"]) },
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "SidefolkCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .target(name: "SidefolkCharacter"),
        .executableTarget(
            name: "SidefolkApp",
            dependencies: [
                "SidefolkCore",
                "SidefolkCharacter",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .executableTarget(name: "sidefolk", dependencies: ["SidefolkCore"]),
        .executableTarget(name: "sidefolk-render", dependencies: ["SidefolkCharacter"]),
        .target(name: "SidefolkExtensionKit", path: "extensions/Kit"),
        // The tests run the built programs in their sandbox, and read their logic directly.
        .testTarget(name: "SidefolkCoreTests", dependencies: ["SidefolkCore"] + builtInExtensions.map { .target(name: "ext-\($0)") }),
        .testTarget(name: "SidefolkCharacterTests", dependencies: ["SidefolkCharacter"]),
    ] + builtInExtensions.map { .executableTarget(name: "ext-\($0)", dependencies: ["SidefolkExtensionKit"], path: "extensions/\($0)/Sources") }
)
