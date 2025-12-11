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
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.8.1")
    ],
    targets: [
        .executableTarget(
            name: "OpenDictation",
            dependencies: [
                "KeyboardShortcuts",
                "whisper",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/OpenDictation",
            exclude: ["Info.plist"],
            resources: [
                .copy("Resources/Sounds"),
                .copy("Resources/Models")
            ],
            cSettings: [
                .unsafeFlags(["-Wno-shorten-64-to-32"])
            ]
        ),
        // whisper.cpp XCFramework - built via `make whisper`
        .binaryTarget(
            name: "whisper",
            path: "deps/whisper.cpp/build-apple/whisper.xcframework"
        )
    ]
)
