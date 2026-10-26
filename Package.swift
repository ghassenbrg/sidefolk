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
        .testTarget(name: "SidefolkCoreTests", dependencies: ["SidefolkCore"]),
        .testTarget(name: "SidefolkCharacterTests", dependencies: ["SidefolkCharacter"]),
    ]
)
