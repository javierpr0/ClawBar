// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "clawbar",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "clawbar",
            path: "Sources/clawbar"
        )
    ]
)
