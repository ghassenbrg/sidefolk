// swift-tools-version: 6.2
import PackageDescription

/// A Sidefolk extension built on the Kit, on its own. `Kit/` is a copy of sidefolk/extensions/Kit (build.sh copies
/// it). In the add-on gallery the same `Sources/` go in sidefolk-addons/extensions/<name>/Sources and its Package.swift
/// builds them instead.
let package = Package(
    name: "WaterTally",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "SidefolkExtensionKit", path: "Kit"),
        .executableTarget(name: "ext-water-tally", dependencies: ["SidefolkExtensionKit"], path: "Sources"),
        .testTarget(name: "WaterTallyTests", dependencies: ["ext-water-tally"], path: "Tests"),
    ]
)
