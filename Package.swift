// swift-tools-version: 6.1
import PackageDescription

#if os(macOS)
// The real app. This branch is what a Mac — the user's machine and the
// macOS CI job — builds; it is unchanged in shape from before the manifest
// grew its Linux half below.
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
            // Golden transcripts, read via #filePath (not Bundle) so the
            // recorder can write them back — excluded to keep SPM from
            // treating them as unhandled resources.
            exclude: ["Fixtures"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
#else
// Any non-Mac host (an agent's Linux box, the Linux CI job) builds the pure
// core — Core/, Logic/, Models/, Rehearsal/ — as a library with the *same
// module name*, so the entire test suite and the rehearsal harness run
// without a Mac. Views/, Services/, main.swift and BreakOverlayManager.swift
// are macOS-only (AppKit / SwiftUI / Combine / CoreAudio) and are excluded;
// every decision the user can see is made in the files that build here,
// which is what makes an off-screen rehearsal of the app possible at all
// (PURPOSE principle 9).
let package = Package(
    name: "DynamicPomodoro",
    // Declared (but never linked) so resolution keeps the same graph as the
    // macOS branch — without this, a Linux `swift build` prunes Sparkle's
    // pin out of Package.resolved and dirties the tree.
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(
            name: "DynamicPomodoro",
            path: "Sources/DynamicPomodoro",
            exclude: ["Views", "Services", "main.swift", "BreakOverlayManager.swift"],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // `swift run rehearse` — thin CLI over Rehearsal/. On macOS the same
        // entry point is reached via `swift run DynamicPomodoro rehearse`
        // (a second executable product would break plain `swift run` there).
        .executableTarget(
            name: "rehearse",
            dependencies: ["DynamicPomodoro"],
            path: "Sources/rehearse",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "DynamicPomodoroTests",
            dependencies: ["DynamicPomodoro"],
            // Golden transcripts, read via #filePath (not Bundle) so the
            // recorder can write them back — excluded to keep SPM from
            // treating them as unhandled resources.
            exclude: ["Fixtures"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
#endif
