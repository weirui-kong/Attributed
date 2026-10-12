// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import CoreGraphics

public extension Attributed {
// NSTextAlignment raw values differ between UIKit and AppKit, so the library
// defines stable values that can cross into the engine unchanged.
enum TextAlignment: UInt8, Hashable, Sendable {
    case natural
    case left
    case center
    case right
    case justified
}

enum WritingDirection: UInt8, Hashable, Sendable {
    case natural
    case leftToRight
    case rightToLeft
}

// Underlines are drawn by the engine as decorations rather than by the
// platform, so they can be filled with gradients.
struct UnderlineStyle: Hashable, Sendable {
    public enum Lines: UInt8, Hashable, Sendable {
        case single
        case double
    }

    public enum Pattern: UInt8, Hashable, Sendable {
        case solid
        case dot
        case dash
        case dashDot
        case dashDotDot
    }

    // Applies to both ends of every drawn segment, including each dash and
    // dot. Adjacent runs on one line with an equal underline and fill are
    // merged into one segment first, so run boundaries never show caps.
    public enum Corners: Hashable, Sendable {
        case square
        // Clamped to half the drawn thickness.
        case radius(CGFloat)
        // Half the drawn thickness, whatever the thickness resolves to.
        case capsule
    }

    public var lines: Lines
    public var pattern: Pattern
    // Nil uses the font's underline thickness.
    public var thickness: CGFloat?
    public var corners: Corners

    public init(
        lines: Lines = .single,
        pattern: Pattern = .solid,
        thickness: CGFloat? = nil,
        corners: Corners = .square
    ) {
        precondition(thickness.map { $0.isFinite && $0 > 0 } ?? true)

        if case let .radius(radius) = corners {
            precondition(radius.isFinite && radius >= 0)
        }

        self.lines = lines
        self.pattern = pattern
        self.thickness = thickness
        self.corners = corners
    }

    public static let single = Self()
    public static let double = Self(lines: .double)
}
}

extension Attributed {
enum Fill {
    case color(PlatformColor)
    case gradient(TextGradient)

    func lowered(into builder: inout IR.Builder) -> IR.Fill {
        switch self {
        case let .color(color):
            return .color(builder.color(color))
        case let .gradient(gradient):
            return .gradient(gradient.lowered(into: &builder))
        }
    }
}

// DSL nodes keep platform values until lowering registers them as resources.
struct InlineStyle {
    var font: PlatformFont?
    var foreground: Fill?
    var backgroundColor: PlatformColor?
    var kern: CGFloat?
    var baselineOffset: CGFloat?
    var underline: UnderlineStyle?
    var underlineFill: Fill?

    func lowered(into builder: inout IR.Builder) -> IR.TextStyle {
        var result = IR.TextStyle()
        result.font = font.map { builder.font($0) }
        result.foreground = foreground?.lowered(into: &builder)
        result.backgroundColor = backgroundColor.map { builder.color($0) }
        result.kern = kern.map(Double.init)
        result.baselineOffset = baselineOffset.map(Double.init)
        result.underline = underline
        result.underlineFill = underlineFill?.lowered(into: &builder)
        return result
    }
}

protocol InlineStyled {
    var inlineStyle: InlineStyle { get set }
}
}

extension Attributed.InlineStyled {
    func withStyle(_ update: (inout Attributed.InlineStyle) -> Void) -> Self {
        var copy = self
        update(&copy.inlineStyle)
        return copy
    }
}
