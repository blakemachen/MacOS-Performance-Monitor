// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PerfMonitor",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure data layer: SMC temperatures + mach CPU/memory sampling.
        .target(
            name: "PerfKit",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        // The SwiftUI app.
        .executableTarget(
            name: "PerfMonitor",
            dependencies: ["PerfKit"]
        ),
        // Headless helper to validate sensor reads from the terminal.
        .executableTarget(
            name: "smcdump",
            dependencies: ["PerfKit"]
        ),
    ]
)
