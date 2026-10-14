// swift-tools-version: 6.0
// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import PackageDescription

// Swift is a thin top layer; heavy work lives in the ObjC++ and C++ targets.
//
//   Attributed (facade)
//   ├─ AttributedUI ──────── AttributedViewObjC ─┐
//   └─ AttributedCore ────── AttributedEngineObjC ┴─ AttributedEngine (C++)
let package = Package(
    name: "Attributed",
    platforms: [
        .iOS(.v15),
        .macOS(.v13)
    ],
    products: [
        .library(name: "Attributed", targets: ["Attributed"]),
        // DSL and layout without views, for example to measure off the main thread.
        .library(name: "AttributedCore", targets: ["AttributedCore"]),
        .library(name: "AttributedUI", targets: ["AttributedUI"])
    ],
    targets: [
        .target(
            name: "Attributed",
            dependencies: ["AttributedCore", "AttributedUI"]
        ),
        .target(
            name: "AttributedCore",
            dependencies: ["AttributedEngineObjC"]
        ),
        .target(
            name: "AttributedUI",
            dependencies: ["AttributedCore", "AttributedEngineObjC", "AttributedViewObjC"]
        ),
        .target(
            name: "AttributedEngineObjC",
            dependencies: ["AttributedEngine"],
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedFramework("UIKit", .when(platforms: [.iOS])),
                .linkedFramework("AppKit", .when(platforms: [.macOS]))
            ]
        ),
        .target(
            name: "AttributedViewObjC",
            dependencies: ["AttributedEngineObjC"],
            // Compiled into default.metallib; building needs the Metal
            // Toolchain (xcodebuild -downloadComponent MetalToolchain).
            resources: [.process("ATRNumericText.metal")],
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("Metal"),
                .linkedFramework("UIKit", .when(platforms: [.iOS])),
                .linkedFramework("AppKit", .when(platforms: [.macOS]))
            ]
        ),
        .target(
            name: "AttributedEngine",
            linkerSettings: [
                .linkedFramework("CoreFoundation"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreText")
            ]
        ),
        .testTarget(
            name: "AttributedCoreTests",
            dependencies: ["AttributedCore", "AttributedEngineObjC"]
        ),
        .testTarget(
            name: "AttributedUITests",
            dependencies: ["AttributedUI", "AttributedCore", "AttributedViewObjC", "AttributedEngineObjC"]
        ),
        .testTarget(
            name: "AttributedEngineTests",
            dependencies: ["AttributedEngineObjC", "AttributedEngine"]
        ),
        .testTarget(
            name: "AttributedViewObjCTests",
            dependencies: ["AttributedViewObjC", "AttributedEngineObjC"]
        )
    ],
    cxxLanguageStandard: .cxx20
)
