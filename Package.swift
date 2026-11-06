// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Tasky",
    platforms: [.macOS(.v14)],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0")],
    targets: [
        .executableTarget(name: "Tasky", dependencies: [.product(name: "Sparkle", package: "Sparkle")],
                          path: "Sources/Tasky", resources: [.process("Resources")],
                          // .app 안의 Contents/Frameworks/Sparkle.framework를 찾게 한다(scripts/make-app.sh)
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])])
    ]
)
