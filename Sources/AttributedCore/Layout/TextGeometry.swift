// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import CoreGraphics
import Foundation
internal import AttributedEngineObjC

public extension Attributed {
// Which visual place an offset means when it has two: the end of one line
// and the start of the next at a soft break, or the two sides of a bidi
// boundary. Upstream belongs to the preceding character.
enum TextAffinity: Hashable, Sendable {
    case upstream
    case downstream
}

// A document-global UTF-16 offset, where paragraphs are joined by one
// newline and each attachment is one U+FFFC.
struct TextPosition: Hashable, Sendable {
    public var offset: Int
    public var affinity: TextAffinity

    public init(offset: Int, affinity: TextAffinity = .downstream) {
        self.offset = offset
        self.affinity = affinity
    }
}

enum TextGranularity: Hashable, Sendable {
    // One grapheme cluster: never splits a composed character sequence or an
    // emoji ZWJ sequence.
    case character
    case word
    case sentence
    case line
    // Excludes the newline separator.
    case paragraph
}

struct LineMetrics: Hashable, Sendable {
    public let index: Int
    public let paragraphIndex: Int
    // Document-global; for a truncated line, only the text it shows.
    public let range: NSRange
    // Typographic frame: origin x, line top, used width, line height.
    public let frame: CGRect
    public let baseline: CGFloat
    public let isTruncated: Bool
}

struct SelectionRect: Hashable, Sendable {
    public let rect: CGRect
    public let lineIndex: Int
    public let isRightToLeft: Bool
    public let containsStart: Bool
    public let containsEnd: Bool
}
}

// Offsets use the document's UTF-16 index space, the same as
// `InteractionEvent.range`; geometry is in layout coordinates, which equal
// the text view's. Safe on any thread.
public extension Attributed.TextLayout {
    var textLength: Int {
        Int(engine.textLength)
    }

    func text(in range: NSRange) -> String {
        engine.document.text(in: range)
    }

    // The drawn text; excludes text cut by truncation or container limits.
    var visibleRange: NSRange {
        engine.visibleRange
    }

    func line(at index: Int) -> Attributed.LineMetrics {
        precondition(index >= 0 && index < lineCount, "Line index out of range.")
        let info = engine.line(at: UInt(index))
        return Attributed.LineMetrics(
            index: index,
            paragraphIndex: Int(info.paragraph),
            range: engine.rangeOfLine(at: UInt(index)),
            frame: info.frame,
            baseline: info.baseline,
            isTruncated: info.truncated.boolValue
        )
    }

    // Nil in the gap between lines and outside the text.
    func lineIndex(atY y: CGFloat) -> Int? {
        found(engine.lineIndexAt(y: y))
    }

    // Nil past the visible text.
    func lineIndex(containing position: Attributed.TextPosition) -> Int? {
        guard position.offset >= 0 else {
            return nil
        }

        return found(engine.lineIndexContaining(position.engineValue))
    }

    // Lines whose frames overlap `rect` vertically.
    func lineIndexes(in rect: CGRect) -> Range<Int> {
        guard !rect.isNull else {
            return 0..<0
        }

        let range = engine.lineIndexesBetweenMinY(rect.minY, maxY: rect.maxY)
        return range.location..<NSMaxRange(range)
    }

    // The grapheme cluster under `point`; nil off glyphs, in line gaps, and
    // on a truncation token.
    func characterIndex(at point: CGPoint) -> Int? {
        found(engine.characterIndex(at: point))
    }

    // Snaps to the nearest line and to grapheme boundaries.
    func closestPosition(to point: CGPoint) -> Attributed.TextPosition {
        Attributed.TextPosition(engine.closestPosition(to: point))
    }

    // Zero width and the line's typographic height. A hidden offset sits
    // before the truncation token.
    func caretRect(for position: Attributed.TextPosition) -> CGRect {
        engine.caretRect(for: position.engineValue)
    }

    // Only the visible part of `range` produces rects; newline separators
    // and empty lines produce none. `rect` limits the result to the lines it
    // overlaps vertically.
    func selectionRects(for range: NSRange, in rect: CGRect? = nil) -> [Attributed.SelectionRect] {
        let bounds = rect ?? CGRect(x: 0, y: -CGFloat.infinity, width: 0, height: .infinity)

        guard !bounds.isNull else {
            return []
        }

        return engine.selectionRects(for: range, minY: bounds.minY, maxY: bounds.maxY).map { value in
            var selection = ATRSelectionRect()
            value.getValue(&selection, size: MemoryLayout<ATRSelectionRect>.size)
            return Attributed.SelectionRect(
                rect: selection.rect,
                lineIndex: Int(selection.line),
                isRightToLeft: selection.rightToLeft.boolValue,
                containsStart: selection.containsStart.boolValue,
                containsEnd: selection.containsEnd.boolValue
            )
        }
    }

    // `.null` when the range shows no rects.
    func boundingRect(for range: NSRange) -> CGRect {
        engine.boundingRect(for: range)
    }

    // Nil past the end of the text, for hidden text at line granularity, and
    // for character, word, or sentence at the end of the text. A separator
    // is its own character but no word or sentence.
    func range(enclosing offset: Int, granularity: Attributed.TextGranularity) -> NSRange? {
        guard offset >= 0 else {
            return nil
        }

        let range = engine.rangeEnclosingIndex(UInt(offset), granularity: granularity.engineValue)
        return range.location == NSNotFound ? nil : range
    }
}

private func found(_ index: UInt) -> Int? {
    index == UInt(NSNotFound) ? nil : Int(index)
}

private extension Attributed.TextPosition {
    init(_ value: ATRTextPosition) {
        self.init(offset: Int(value.offset), affinity: value.affinity == .upstream ? .upstream : .downstream)
    }

    var engineValue: ATRTextPosition {
        ATRTextPosition(
            offset: UInt(max(offset, 0)),
            affinity: affinity == .upstream ? .upstream : .downstream
        )
    }
}

private extension Attributed.TextGranularity {
    var engineValue: ATRTextGranularity {
        switch self {
        case .character: .character
        case .word: .word
        case .sentence: .sentence
        case .line: .line
        case .paragraph: .paragraph
        }
    }
}
