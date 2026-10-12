// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import CoreGraphics

public extension Attributed {
// Unit coordinates in the gradient's bounding rect; (0, 0) is the top-left.
struct GradientPoint: Hashable, Sendable {
    public var x: CGFloat
    public var y: CGFloat

    public init(x: CGFloat, y: CGFloat) {
        self.x = x
        self.y = y
    }

    public static let topLeft = Self(x: 0, y: 0)
    public static let top = Self(x: 0.5, y: 0)
    public static let topRight = Self(x: 1, y: 0)
    public static let left = Self(x: 0, y: 0.5)
    public static let center = Self(x: 0.5, y: 0.5)
    public static let right = Self(x: 1, y: 0.5)
    public static let bottomLeft = Self(x: 0, y: 1)
    public static let bottom = Self(x: 0.5, y: 1)
    public static let bottomRight = Self(x: 1, y: 1)
}

// The lookup space for joining gradients. Within one scope, runs whose
// gradients are equal (scope included) are drawn as one continuous gradient
// laid out over the union of their typographic bounds; they need not be
// adjacent.
enum GradientScope: UInt8, Hashable, Sendable {
    // Matching runs within one CTLine.
    case line
    // Matching runs within one paragraph, across its lines.
    case paragraph
    // Matching runs across the whole document.
    // WARNING: every matching run must be laid out before any of them can be
    // drawn, which defeats incremental and tiled rendering. Very expensive for
    // long text; use with care.
    case document
}

// Fills glyphs in place of the foreground color. Emoji keep their own colors
// unless the hosting text view opts them into gradients.
struct TextGradient {
    let colors: [PlatformColor]
    let locations: [CGFloat]?
    let startPoint: GradientPoint
    let endPoint: GradientPoint
    let scope: GradientScope

    // Without `locations`, colors are spaced evenly.
    public init(
        colors: [PlatformColor],
        locations: [CGFloat]? = nil,
        startPoint: GradientPoint = .left,
        endPoint: GradientPoint = .right,
        scope: GradientScope = .paragraph
    ) {
        precondition(colors.count >= 2, "A gradient needs at least two colors.")

        if let locations {
            precondition(
                locations.count == colors.count,
                "Gradient locations must match the number of colors."
            )
            precondition(
                zip(locations, locations.dropFirst()).allSatisfy { $0 <= $1 }
                    && locations.allSatisfy { (0...1).contains($0) },
                "Gradient locations must be ascending values in 0...1."
            )
        }

        self.colors = colors
        self.locations = locations
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.scope = scope
    }

    func lowered(into builder: inout IR.Builder) -> IR.GradientRef {
        builder.gradient(
            IR.Gradient(
                colors: colors.map { builder.color($0) },
                locations: locations?.map(Double.init),
                startX: Double(startPoint.x),
                startY: Double(startPoint.y),
                endX: Double(endPoint.x),
                endY: Double(endPoint.y),
                scope: scope
            )
        )
    }
}
}
