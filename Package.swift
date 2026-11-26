// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Screech",
    platforms: [.macOS(.v15)],
    targets: [
        // Pure DSP + motion analysis. No AppKit / AVFoundation, so it can be tested and rendered offline.
        .target(name: "ScreechDSP"),
        // The menu bar app.
        .executableTarget(name: "Screech", dependencies: ["ScreechDSP"]),
        // Renders WAV previews of every material from a scripted, uneven hand motion.
        .executableTarget(name: "screech-render", dependencies: ["ScreechDSP"]),
        .testTarget(name: "ScreechDSPTests", dependencies: ["ScreechDSP"]),
    ],
    swiftLanguageModes: [.v5]
)
