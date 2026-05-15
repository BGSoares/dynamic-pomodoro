// swift-tools-version: 5.9
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
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "DynamicPomodoroTests",
            dependencies: ["DynamicPomodoro"]
        ),
    ]
)
