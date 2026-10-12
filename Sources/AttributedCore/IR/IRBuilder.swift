// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import Foundation
package import AttributedEngineObjC

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public extension Attributed.IR {
// Thin wrapper over the engine builder. Structural rules (no nested
// paragraphs, inline content only inside a paragraph) are enforced by the
// engine; only Swift closures and image sources are kept here.
struct Builder {
    private let engine = ATRDocumentBuilder()
    private var interactions: [Attributed.Interaction] = []
    private var gestures: [Attributed.Gesture] = []
    private var imageSources: [Attributed.ImageSource] = []

    init() {}

    public mutating func paragraph(
        _ paragraphStyle: ParagraphStyle = ParagraphStyle(),
        textStyle: TextStyle = TextStyle(),
        _ body: (inout Builder) -> Void
    ) {
        engine.beginParagraph(paragraphStyle.engineValue, textStyle: textStyle.engineValue)
        body(&self)
        engine.endParagraph()
    }

    public mutating func span(
        _ span: Span,
        _ body: (inout Builder) -> Void
    ) {
        engine.pushSpan(
            span.textStyle.engineValue,
            interaction: span.interaction?.rawValue ?? ATRNoInteraction
        )
        body(&self)
        engine.popSpan()
    }

    public mutating func text(_ string: String) {
        engine.appendText(string)
    }

    @discardableResult
    public mutating func image(
        _ descriptor: AttachmentDescriptor,
        source: Attributed.ImageSource
    ) -> Attributed.AttachmentID {
        var value = descriptor.engineValue

        switch source {
        case let .resolved(image):
            value.pipeline = .image
            value.fields.insert(.contentSize)
            value.contentWidth = Double(image.size.width)
            value.contentHeight = Double(image.size.height)
        case .defer:
            value.pipeline = .asyncImage
        }

        let rawValue = engine.appendAttachment(
            value,
            accessibilityLabel: descriptor.accessibilityLabel
        )
        imageSources.append(source)
        return Attributed.AttachmentID(rawValue: rawValue)
    }

    public mutating func font(_ font: PlatformFont) -> FontRef {
        FontRef(index: engine.register(font))
    }

    public mutating func color(_ color: PlatformColor) -> ColorRef {
        ColorRef(index: engine.register(color))
    }

    public mutating func gradient(_ gradient: Gradient) -> GradientRef {
        // The engine reads `locations` with the color count.
        precondition(gradient.colors.count >= 2, "A gradient needs at least two colors.")
        precondition(
            gradient.locations.map { $0.count == gradient.colors.count } ?? true,
            "Gradient locations must match the number of colors."
        )
        let colors = gradient.colors.map(\.index)
        let descriptor = ATRGradientDescriptor(
            startX: gradient.startX,
            startY: gradient.startY,
            endX: gradient.endX,
            endY: gradient.endY,
            scope: ATRGradientScope(rawValue: gradient.scope.rawValue)!
        )
        let index = colors.withUnsafeBufferPointer { colors in
            if let locations = gradient.locations {
                return locations.withUnsafeBufferPointer { locations in
                    engine.registerGradient(
                        withColors: colors.baseAddress!,
                        locations: locations.baseAddress,
                        count: UInt(colors.count),
                        descriptor: descriptor
                    )
                }
            }

            return engine.registerGradient(
                withColors: colors.baseAddress!,
                locations: nil,
                count: UInt(colors.count),
                descriptor: descriptor
            )
        }

        return GradientRef(index: index)
    }

    // The engine assigns the ID; the Swift handler is stored at the same
    // index.
    public mutating func register(
        _ interaction: Attributed.Interaction,
        gesture: Attributed.Gesture = .tap()
    ) -> Attributed.InteractionID {
        let rawValue = engine.registerInteraction(with: gesture.engineValue)
        precondition(rawValue == UInt32(interactions.count))
        interactions.append(interaction)
        gestures.append(gesture)
        return Attributed.InteractionID(rawValue: rawValue)
    }

    func finish() -> LoweredText {
        LoweredText(
            document: Document(engine: engine.finish()),
            interactions: interactions,
            gestures: gestures,
            imageSources: imageSources
        )
    }
}
}

extension Attributed.IR.Fill {
    var engineValue: ATRFill {
        switch self {
        case let .color(color):
            return ATRFill(kind: .color, index: color.index)
        case let .gradient(gradient):
            return ATRFill(kind: .gradient, index: gradient.index)
        }
    }
}

extension Attributed.IR.TextStyle {
    var engineValue: ATRTextStyle {
        var result = ATRTextStyle()

        if let font {
            result.fields.insert(.font)
            result.font = font.index
        }

        if let foreground {
            result.fields.insert(.foreground)
            result.foreground = foreground.engineValue
        }

        if let backgroundColor {
            result.fields.insert(.backgroundColor)
            result.backgroundColor = backgroundColor.index
        }

        if let kern {
            result.fields.insert(.kern)
            result.kern = kern
        }

        if let baselineOffset {
            result.fields.insert(.baselineOffset)
            result.baselineOffset = baselineOffset
        }

        if let underline {
            result.fields.insert(.underline)
            result.underline = ATRUnderline(
                lines: ATRUnderlineLines(rawValue: underline.lines.rawValue)!,
                pattern: ATRUnderlinePattern(rawValue: underline.pattern.rawValue)!,
                thickness: underline.thickness.map(Double.init) ?? 0,
                corners: .square,
                cornerRadius: 0
            )

            switch underline.corners {
            case .square:
                break
            case let .radius(radius):
                result.underline.corners = .radius
                result.underline.cornerRadius = Double(radius)
            case .capsule:
                result.underline.corners = .capsule
            }
        }

        if let underlineFill {
            result.fields.insert(.underlineFill)
            result.underlineFill = underlineFill.engineValue
        }

        return result
    }
}

extension Attributed.IR.ParagraphStyle {
    var engineValue: ATRParagraphStyle {
        var result = ATRParagraphStyle()

        if let alignment {
            result.fields.insert(.alignment)
            result.alignment = ATRTextAlignment(rawValue: alignment.rawValue)!
        }

        if let writingDirection {
            result.fields.insert(.writingDirection)
            result.writingDirection = ATRWritingDirection(rawValue: writingDirection.rawValue)!
        }

        if let lineSpacing {
            result.fields.insert(.lineSpacing)
            result.lineSpacing = lineSpacing
        }

        if let paragraphSpacing {
            result.fields.insert(.paragraphSpacing)
            result.paragraphSpacing = paragraphSpacing
        }

        return result
    }
}

extension Attributed.IR.AttachmentDescriptor {
    var engineValue: ATRAttachmentDescriptor {
        var result = ATRAttachmentDescriptor()

        switch size {
        case let .fixed(width, height):
            result.sizeKind = .fixed
            result.width = Double(width)
            result.height = Double(height)
        case let .adaptive(maxWidth, maxHeight):
            result.sizeKind = .adaptive

            if let maxWidth {
                result.fields.insert(.maxWidth)
                result.maxWidth = Double(maxWidth)
            }

            if let maxHeight {
                result.fields.insert(.maxHeight)
                result.maxHeight = Double(maxHeight)
            }
        }

        switch alignment {
        case .baseline:
            result.alignmentKind = .baseline
        case .center:
            result.alignmentKind = .center
        case .top:
            result.alignmentKind = .top
        case .bottom:
            result.alignmentKind = .bottom
        case let .offset(value):
            result.alignmentKind = .offset
            result.alignmentOffset = Double(value)
        }

        return result
    }
}

extension Attributed.Gesture {
    var engineValue: ATRGesture {
        switch self {
        case let .tap(count):
            return ATRGesture(kind: .tap, tapCount: UInt32(clamping: count), minimumPressDuration: 0)
        case let .longPress(minimumDuration):
            return ATRGesture(kind: .longPress, tapCount: 0, minimumPressDuration: minimumDuration)
        }
    }
}
