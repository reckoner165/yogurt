// swift-tools-version:5.8
import PackageDescription

let package = Package(
    name: "Yogurt",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Yogurt", path: "Sources/Yogurt")
    ]
)
