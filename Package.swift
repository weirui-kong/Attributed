// swift-tools-version: 5.9
// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import PackageDescription

let package = Package(
    name: "Attributed",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
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
            name: "AttributedTextKit",
            targets: ["AttributedTextKit"]
        ),
        .library(
            name: "AttributedSwiftUI",
            targets: ["AttributedSwiftUI"]
        ),
        .library(
            name: "AttributedUtility",
            targets: ["AttributedUtility"]
        )
    ],
    targets: [
        .target(
            name: "Attributed",
            dependencies: [
                "AttributedCore",
                "AttributedTextKit",
                "AttributedSwiftUI"
            ]
        ),
        .target(
            name: "AttributedCore",
            path: "Sources/Core"
        ),
        .target(
            name: "AttributedTextKit",
            dependencies: ["AttributedCore"],
            path: "Sources/TextKit"
        ),
        .target(
            name: "AttributedSwiftUI",
            dependencies: [
                "AttributedCore",
                "AttributedTextKit"
            ],
            path: "Sources/SwiftUI"
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
            name: "AttributedTextKitTests",
            dependencies: ["AttributedTextKit"],
            path: "Tests/TextKitTests"
        ),
        .testTarget(
            name: "AttributedUtilityTests",
            dependencies: ["AttributedUtility"],
            path: "Tests/UtilityTests"
        )
    ]
)
