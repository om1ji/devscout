// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "devscout",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "devscout", path: "Sources/devscout")
    ]
)
