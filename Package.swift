// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Kongpod",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Kongpod", path: "Sources/Kongpod")
    ]
)
