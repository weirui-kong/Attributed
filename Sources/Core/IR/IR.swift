// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import Foundation
internal import AttributedEngineObjC

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public extension Attributed {
// The IR is the boundary between the Swift DSL and the engine. The Swift
// types here are plain values handed to `Builder`; the document itself is
// stored, validated, and deduplicated in engine memory.
enum IR {}
}

public extension Attributed.IR {
// Immutable once built, so it can be laid out on any thread.
struct Document: @unchecked Sendable {
    let engine: ATRDocument

    // Stable ops and gradients first; font and color descriptions follow a
    // "---" line because platform descriptions vary across OS versions.
    public func dump() -> String {
        engine.dump()
    }

    var fontCount: Int {
        Int(engine.fontCount)
    }

    var colorCount: Int {
        Int(engine.colorCount)
    }

    func font(_ font: FontRef) -> PlatformFont {
        engine.font(at: UInt(font.index))
    }

    func color(_ color: ColorRef) -> PlatformColor {
        engine.color(at: UInt(color.index))
    }
}

struct Span: Hashable, Sendable {
    public var textStyle: TextStyle
    // The innermost span with an interaction wins.
    public var interaction: Attributed.InteractionID?

    public init(
        textStyle: TextStyle = TextStyle(),
        interaction: Attributed.InteractionID? = nil
    ) {
        self.textStyle = textStyle
        self.interaction = interaction
    }
}

// A nil field inherits the value from the enclosing scope.
struct TextStyle: Hashable, Sendable {
    public var font: FontRef?
    public var foreground: Fill?
    public var backgroundColor: ColorRef?
    public var kern: Double?
    public var baselineOffset: Double?
    public var underline: Attributed.UnderlineStyle?
    // Nil after inheritance means the underline uses the foreground fill.
    public var underlineFill: Fill?

    public init() {}
}

enum Fill: Hashable, Sendable {
    case color(ColorRef)
    case gradient(GradientRef)
}

struct ParagraphStyle: Hashable, Sendable {
    public var alignment: Attributed.TextAlignment?
    public var writingDirection: Attributed.WritingDirection?
    public var lineSpacing: Double?
    public var paragraphSpacing: Double?

    public init() {}
}

struct FontRef: Hashable, Sendable {
    public let index: Int32
}

struct ColorRef: Hashable, Sendable {
    public let index: Int32
}

struct GradientRef: Hashable, Sendable {
    public let index: Int32
}

// Equal gradients share one `GradientRef`; the engine groups runs for a
// shared gradient rect by comparing refs.
struct Gradient: Hashable, Sendable {
    public var colors: [ColorRef]
    public var locations: [Double]?
    public var startX: Double
    public var startY: Double
    public var endX: Double
    public var endY: Double
    public var scope: Attributed.GradientScope
}

struct AttachmentDescriptor: Hashable, Sendable {
    public var size: Attributed.AttachmentSize
    public var alignment: Attributed.AttachmentAlignment
    public var accessibilityLabel: String?

    public init(
        size: Attributed.AttachmentSize,
        alignment: Attributed.AttachmentAlignment = .baseline,
        accessibilityLabel: String? = nil
    ) {
        self.size = size
        self.alignment = alignment
        self.accessibilityLabel = accessibilityLabel
    }
}

// Lowering output: the engine-facing document plus the Swift-only values
// (closures and image sources) that the IR refers to by identifier.
struct LoweredText {
    public let document: Document
    let interactions: [Attributed.Interaction]
    let gestures: [Attributed.Gesture]
    let imageSources: [Attributed.ImageSource]

    public func interaction(for id: Attributed.InteractionID) -> Attributed.Interaction {
        interactions[Int(id.rawValue)]
    }

    public func gesture(for id: Attributed.InteractionID) -> Attributed.Gesture {
        gestures[Int(id.rawValue)]
    }

    public func imageSource(for id: Attributed.AttachmentID) -> Attributed.ImageSource {
        imageSources[Int(id.rawValue)]
    }
}
}
