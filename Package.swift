// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DynamicPomodoro",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "DynamicPomodoro",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "DynamicPomodoroTests",
            dependencies: ["DynamicPomodoro"]
        ),
    ]
)
