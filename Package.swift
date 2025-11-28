// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Stitcher",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
        .tvOS(.v15),
        .watchOS(.v8)
    ],
    products: [
        .library(
            name: "Stitcher",
            targets: ["Stitcher"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0")
    ],
    targets: [
        .target(
            name: "Stitcher",
            dependencies: ["Yams"]
        ),
        .testTarget(
            name: "StitcherTests",
            dependencies: ["Stitcher"],
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
