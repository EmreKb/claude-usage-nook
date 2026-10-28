// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeUsage",
    platforms: [.macOS(.v14)],
    dependencies: [.package(url: "https://github.com/fatihsen-dev/nook", branch: "main")],
    targets: [
        .executableTarget(name: "ClaudeUsage", dependencies: [.product(name: "NookKit", package: "nook")], path: "Sources"),
    ]
)
