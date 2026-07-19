// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "DynamicPomodoro",
    platforms: [.macOS(.v13)],
    // AutoUpdate (default on) gates the Sparkle dependency. Build with
    // `swift build --disable-default-traits` (or `./build-app.sh --no-sparkle`)
    // for the zero-network work-laptop variant: no updater framework, no
    // outbound connections, and no need for the library-validation-disabling
    // entitlement that exists solely to load ad-hoc-signed Sparkle.framework.
    traits: [
        .default(enabledTraits: ["AutoUpdate"]),
        .trait(name: "AutoUpdate", description: "Embed Sparkle for auto-updates"),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "DynamicPomodoro",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle", condition: .when(traits: ["AutoUpdate"])),
            ],
            resources: [.process("Resources")],
            // Language mode pinned to v5: the tools-version bump (needed for
            // swift-testing under bare Command Line Tools and for traits)
            // must not drag the codebase into strict-concurrency mode as a
            // side effect.
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "DynamicPomodoroTests",
            dependencies: ["DynamicPomodoro"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
