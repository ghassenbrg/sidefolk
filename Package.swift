// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Sidefolk",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "SidefolkApp", targets: ["SidefolkApp"]),
        .executable(name: "sidefolk", targets: ["sidefolk"]),
        .executable(name: "sidefolk-render", targets: ["sidefolk-render"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "SidefolkCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        // Art: the 2D companions' painted parts (D59).
        .target(name: "SidefolkCharacter", resources: [.copy("Art")]),
        .executableTarget(
            name: "SidefolkApp",
            dependencies: [
                "SidefolkCore",
                "SidefolkCharacter",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            // The Play panel's pictures (cups, gem, balloon, trophy), chosen by a board's part, never sent by a game.
            resources: [.copy("Play/Art")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .executableTarget(name: "sidefolk", dependencies: ["SidefolkCore"]),
        .executableTarget(name: "sidefolk-render", dependencies: ["SidefolkCharacter"]),
        .target(name: "SidefolkExtensionKit", path: "extensions/Kit"),
        // Every extension is built and signed in the sidefolk-addons repository (D55, D98); the Kit stays here, where it
        // is changed first, and the tests run the gallery's programs in their sandbox from a checkout beside this one.
        .testTarget(name: "SidefolkCoreTests", dependencies: ["SidefolkCore", "SidefolkExtensionKit"]),
        .testTarget(name: "SidefolkCharacterTests", dependencies: ["SidefolkCharacter"]),
    ]
)
