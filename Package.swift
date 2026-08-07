// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ArenaScreenSaver",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ArenaCore", targets: ["ArenaCore"])
    ],
    targets: [
        .target(
            name: "ArenaCore",
            path: "Sources/ArenaScreenSaver",
            exclude: [
                "ArenaPreferences.swift",
                "ArenaScreenSaverView.swift",
                "ConfigurationWindowController.swift",
                "ImageCanvasView.swift"
            ],
            sources: ["ArenaAPI.swift", "ArenaCache.swift", "ArenaRotationEngine.swift"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ArenaCoreTests",
            dependencies: ["ArenaCore"],
            path: "Tests/ArenaCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
