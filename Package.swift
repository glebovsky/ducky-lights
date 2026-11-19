// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DuckyLights",
    platforms: [.macOS("15.0")],
    products: [
        .library(name: "DuckyKit", targets: ["DuckyKit"]),
        .executable(name: "DuckyLights", targets: ["DuckyLights"]),
        .executable(name: "duckyctl", targets: ["duckyctl"]),
    ],
    targets: [
        // Protocol encoder, key layout, effects, IOKit HID transport. No UI.
        .target(name: "DuckyKit"),
        // SwiftUI app.
        .executableTarget(name: "DuckyLights", dependencies: ["DuckyKit"]),
        // Command-line tool for hardware bring-up and debugging.
        .executableTarget(name: "duckyctl", dependencies: ["DuckyKit"]),
        .testTarget(name: "DuckyKitTests", dependencies: ["DuckyKit"]),
    ]
)
