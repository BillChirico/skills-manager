// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SkillsCore",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "SkillsCore",
            targets: ["SkillsCore"]
        )
    ],
    targets: [
        .target(name: "SkillsCore"),
        .testTarget(
            name: "SkillsCoreTests",
            dependencies: ["SkillsCore"]
        )
    ]
)
