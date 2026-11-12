// swift-tools-version: 6.2
import PackageDescription

// Ur Fonts. macOS 15+, Swift 6 strict concurrency.
// Core has no UI. The app target defaults to the main actor.
let package = Package(
    name: "UrFonts",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "UrFonts", targets: ["UrFonts"]),
        .executable(name: "urfonts-cli", targets: ["urfonts-cli"]),
        .library(name: "UrFontsCore", targets: ["UrFontsCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "UrFontsCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")],
            path: "Sources/UrFontsCore"
        ),
        .executableTarget(
            name: "UrFonts",
            dependencies: ["UrFontsCore"],
            path: "Sources/UrFonts",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .executableTarget(
            name: "urfonts-cli",
            dependencies: ["UrFontsCore"],
            path: "Sources/urfonts-cli"
        ),
        // Fixture generation only. Never linked into the app.
        .target(
            name: "UrFontsFixtures",
            path: "tools/Fixtures"
        ),
        .executableTarget(
            name: "FixtureGen",
            dependencies: ["UrFontsFixtures"],
            path: "tools/FixtureGen"
        ),
        .testTarget(
            name: "UrFontsCoreTests",
            dependencies: [
                "UrFontsCore",
                "UrFontsFixtures",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Tests/UrFontsCoreTests"
        ),
    ]
)
