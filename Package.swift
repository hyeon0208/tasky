// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Tasky",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Tasky", path: "Sources/Tasky")
    ]
)
