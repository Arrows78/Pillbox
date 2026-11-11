// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Pillbox",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", exact: "1.99.1"),
        .package(url: "https://github.com/airbnb/lottie-ios.git", from: "4.5.0")
    ],
    targets: [
        .executableTarget(name: "Pillbox", dependencies: [.product(name: "SwiftTerm", package: "SwiftTerm"), .product(name: "Lottie", package: "lottie-ios")], path: "Sources/Pillbox"),
        .testTarget(name: "PillboxTests", dependencies: ["Pillbox"], path: "Tests/PillboxTests")
    ]
)
