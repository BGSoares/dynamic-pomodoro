// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "DynamicPomodoro",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "DynamicPomodoro",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            resources: [.process("Resources")],
            // Language mode pinned to v5: the tools-version bump (needed for
            // swift-testing under bare Command Line Tools) must not drag the
            // codebase into strict-concurrency mode as a side effect.
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "DynamicPomodoroTests",
            dependencies: ["DynamicPomodoro"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
