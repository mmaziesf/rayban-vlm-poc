// swift-tools-version:5.10
// Platform-neutral port of phone/core (Kotlin). Foundation only → builds and tests on Linux (bot box) AND iOS.
// DAT / LiteRT-LM / AVFoundation stay in the app target (ios/GlanceApp), behind the protocols in Ports.swift.
import PackageDescription

let package = Package(
    name: "GlanceCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "GlanceCore", targets: ["GlanceCore"])],
    targets: [
        .target(name: "GlanceCore"),
        .testTarget(name: "GlanceCoreTests", dependencies: ["GlanceCore"]),
    ]
)
