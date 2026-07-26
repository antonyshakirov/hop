// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Hop",
    platforms: [.macOS(.v14)],
    targets: [
        // HopCore keeps the full optimizer: the timer maths, the parsing rules and
        // everything else with tests behind it lives here, and it costs seconds.
        .target(name: "HopCore"),
        // The app layer builds with -Osize, and that is a 27× difference measured
        // on this tree (2026-07-26): a release build of the UI module took 16m46s
        // with -O and 37s with -Osize, for a binary of exactly the same size
        // (11.6 MB). At -O the optimizer hits a pathological case on this module —
        // 29k lines of SwiftUI closures plus the 18-language string tables — and
        // spends a quarter of an hour inlining what a menu-bar app never notices:
        // the actual work happens inside AppKit and SwiftUI, and Hop's own hot
        // paths are in HopCore, still at -O. -Osize is a shipping Apple
        // optimization level ("Optimize for size" in Xcode), not a debug setting.
        .executableTarget(
            name: "Hop",
            dependencies: ["HopCore"],
            swiftSettings: [.unsafeFlags(["-Osize"], .when(configuration: .release))]
        ),
        .testTarget(name: "HopCoreTests", dependencies: ["HopCore"], resources: [.copy("Fixtures")]),
    ]
)
