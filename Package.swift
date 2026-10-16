// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "appshot-for-agents",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "appshot", targets: ["appshot"])],
    targets: [
        .executableTarget(name: "appshot", path: "Sources/appshot"),
    ]
)
