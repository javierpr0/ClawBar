// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "claude-status-bar",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "claude-status-bar",
            path: "Sources/claude-status-bar"
        )
    ]
)
