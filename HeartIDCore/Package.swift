// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "HeartIDCore",
    platforms: [
        .iOS(.v16),
        .watchOS(.v9),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "HeartIDCore",
            targets: ["HeartIDCore"]
        ),
    ],
    targets: [
        .target(
            name: "HeartIDCore",
            dependencies: [],
            path: "Sources/HeartIDCore"
        ),
        .testTarget(
            name: "HeartIDCoreTests",
            dependencies: ["HeartIDCore"],
            path: "Tests/HeartIDCoreTests"
        ),
    ]
)
