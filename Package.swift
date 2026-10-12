// swift-tools-version: 6.0
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
        )
    ],
    targets: [
        .target(
            name: "Attributed",
            dependencies: ["AttributedCore"],
            path: "Sources/Attributed"
        ),
        .target(
            name: "AttributedCore",
            dependencies: ["AttributedEngineObjC"],
            path: "Sources/Core"
        ),
        .target(
            name: "AttributedEngineObjC",
            dependencies: ["AttributedEngine"],
            path: "Sources/EngineObjC",
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("UIKit", .when(platforms: [.iOS])),
                .linkedFramework("AppKit", .when(platforms: [.macOS]))
            ]
        ),
        .target(
            name: "AttributedEngine",
            path: "Sources/Engine",
            linkerSettings: [
                .linkedFramework("CoreFoundation"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreText")
            ]
        ),
        .testTarget(
            name: "AttributedCoreTests",
            dependencies: ["AttributedCore", "AttributedEngineObjC"],
            path: "Tests/CoreTests"
        ),
        .testTarget(
            name: "AttributedEngineTests",
            dependencies: ["AttributedEngineObjC", "AttributedEngine"],
            path: "Tests/EngineTests"
        )
    ],
    cxxLanguageStandard: .cxx20
)
