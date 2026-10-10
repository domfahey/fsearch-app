// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FSearchKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "FSearchKit", targets: ["FSearchKit"])],
    targets: [
        .target(name: "FSearchKit"),
        .testTarget(name: "FSearchKitTests", dependencies: ["FSearchKit"]),
        // Performance benchmarks; run through scripts/bench.sh (release build).
        .executableTarget(name: "FSearchBench", dependencies: ["FSearchKit"]),
    ]
)
