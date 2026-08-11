// swift-tools-version: 5.9
// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import PackageDescription

let package = Package(
    name: "Attributed",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "Attributed",
            targets: ["Attributed"]
        ),
        .library(
            name: "AttributedCore",
            targets: ["AttributedCore"]
        ),
        .library(
            name: "AttributedUtility",
            targets: ["AttributedUtility"]
        )
    ],
    targets: [
        .target(
            name: "Attributed",
            dependencies: ["AttributedCore"]
        ),
        .target(
            name: "AttributedCore",
            path: "Sources/Core"
        ),
        .target(
            name: "AttributedUtility",
            dependencies: ["AttributedCore"],
            path: "Sources/Utility"
        ),
        .testTarget(
            name: "AttributedTests",
            dependencies: ["Attributed"]
        ),
        .testTarget(
            name: "AttributedCoreTests",
            dependencies: ["AttributedCore"],
            path: "Tests/CoreTests"
        ),
        .testTarget(
            name: "AttributedUtilityTests",
            dependencies: ["AttributedUtility"],
            path: "Tests/UtilityTests"
        )
    ]
)
