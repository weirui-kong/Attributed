// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import CoreGraphics
internal import AttributedEngineObjC

public extension Attributed {
enum LineHeightMode: UInt8, Hashable, Sendable {
    // Typographic font metrics; tall glyphs may overlap neighboring lines,
    // as in UIKit text views.
    case typographic
    // Lines grow to contain every glyph's actual bounds, for example the
    // stacked marks of Thai or Myanmar.
    case glyphBounds
}

struct TextContainer: Hashable, Sendable {
    // Positive; `.infinity` disables wrapping and alignment.
    public var width: CGFloat
    public var maxHeight: CGFloat
    // Zero means unlimited.
    public var maximumNumberOfLines: Int
    // Appended where content is cut, styled like the character it follows.
    public var truncationToken: String
    public var lineHeightMode: LineHeightMode

    public init(
        width: CGFloat,
        maxHeight: CGFloat = .infinity,
        maximumNumberOfLines: Int = 0,
        truncationToken: String = "\u{2026}",
        lineHeightMode: LineHeightMode = .typographic
    ) {
        precondition(width > 0, "A text container needs a positive width.")
        precondition(maxHeight >= 0)
        precondition(maximumNumberOfLines >= 0)
        self.width = width
        self.maxHeight = maxHeight
        self.maximumNumberOfLines = maximumNumberOfLines
        self.truncationToken = truncationToken
        self.lineHeightMode = lineHeightMode
    }
}

// Immutable; the engine object it wraps is never mutated after creation.
struct TextLayout: @unchecked Sendable {
    let engine: ATRTextLayout

    // Used width and total height, unrounded.
    public var size: CGSize {
        engine.size
    }

    public var lineCount: Int {
        Int(engine.lineCount)
    }

    public var isTruncated: Bool {
        engine.isTruncated
    }
}
}

// Safe to call on any thread: layout runs on CoreText inside the engine.
public extension Attributed.IR.Document {
    func layout(in container: Attributed.TextContainer) -> Attributed.TextLayout {
        let value = ATRTextContainer(
            width: Double(container.width),
            maxHeight: Double(container.maxHeight),
            maximumNumberOfLines: UInt32(clamping: container.maximumNumberOfLines),
            lineHeightMode: ATRLineHeightMode(rawValue: container.lineHeightMode.rawValue)!
        )

        return Attributed.TextLayout(
            engine: engine.layout(with: value, truncationToken: container.truncationToken)
        )
    }
}

public extension Attributed.IR.LoweredText {
    func layout(in container: Attributed.TextContainer) -> Attributed.TextLayout {
        document.layout(in: container)
    }
}
