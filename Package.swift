// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Hop",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "HopCore"),
        .executableTarget(name: "Hop", dependencies: ["HopCore"]),
        .testTarget(name: "HopCoreTests", dependencies: ["HopCore"]),
    ]
)
