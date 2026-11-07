// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Pillbox",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Pillbox", path: "Sources/Pillbox")
    ]
)
