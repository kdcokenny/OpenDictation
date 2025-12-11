// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenDictation",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "OpenDictation", targets: ["OpenDictation"])
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
        .package(url: "https://github.com/sindresorhus/Settings", from: "3.1.0"),
        .package(url: "https://github.com/sindresorhus/Defaults", from: "8.0.0")
    ],
    targets: [
        .executableTarget(
            name: "OpenDictation",
            dependencies: [
                "KeyboardShortcuts",
                "Settings",
                "Defaults"
            ],
            path: "Sources/OpenDictation",
            exclude: ["Info.plist"],
            resources: [
                .copy("Resources/Sounds")
            ]
        )
    ]
)
