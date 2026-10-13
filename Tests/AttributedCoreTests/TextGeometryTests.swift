// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import Foundation
import XCTest
@testable import AttributedCore

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

private typealias AttributedText = Attributed.AttributedText
private typealias Image = Attributed.Image
private typealias Paragraph = Attributed.Paragraph
private typealias Spacer = Attributed.Spacer
private typealias Text = Attributed.Text
private typealias TextContainer = Attributed.TextContainer
private typealias TextPosition = Attributed.TextPosition

private let longText = "The quick brown fox jumps over the lazy dog and keeps running across the field."
private var font: PlatformFont {
    .systemFont(ofSize: 16)
}

private func layout(_ paragraphs: [String], container: TextContainer) -> Attributed.TextLayout {
    AttributedText {
        for text in paragraphs {
            Paragraph { text }
                .font(font)
        }
    }
    .lower()
    .layout(in: container)
}

final class TextGeometryTests: XCTestCase {
    func testLineMetricsDescribeEveryLine() {
        let layout = layout([longText, "Tail"], container: TextContainer(width: 120))
        var expectedLocation = 0

        for index in 0..<layout.lineCount {
            let line = layout.line(at: index)
            XCTAssertEqual(line.index, index)

            if index > 0, line.paragraphIndex != layout.line(at: index - 1).paragraphIndex {
                expectedLocation += 1
            }

            XCTAssertEqual(line.range.location, expectedLocation)
            XCTAssertGreaterThan(line.frame.height, 0)
            XCTAssertGreaterThan(line.baseline, line.frame.minY)
            XCTAssertLessThan(line.baseline, line.frame.maxY)
            XCTAssertFalse(line.isTruncated)
            expectedLocation = NSMaxRange(line.range)
        }

        XCTAssertEqual(expectedLocation, layout.textLength)
        XCTAssertEqual(layout.line(at: layout.lineCount - 1).paragraphIndex, 1)
    }

    func testTextUsesTheDocumentIndexSpace() {
        let layout = layout(["Hello", "World"], container: TextContainer(width: 300))

        XCTAssertEqual(layout.textLength, 11)
        XCTAssertEqual(layout.text(in: NSRange(location: 0, length: 11)), "Hello\nWorld")
        XCTAssertEqual(layout.text(in: NSRange(location: 4, length: 3)), "o\nW")
        XCTAssertEqual(layout.visibleRange, NSRange(location: 0, length: 11))
    }

    func testHighlightingASearchMatch() {
        let layout = layout([longText], container: TextContainer(width: 120))
        let text = layout.text(in: NSRange(location: 0, length: layout.textLength))
        let match = NSRange(text.range(of: "lazy dog")!, in: text)
        let rects = layout.selectionRects(for: match)

        XCTAssertFalse(rects.isEmpty)
        XCTAssertTrue(rects.first!.containsStart)
        XCTAssertTrue(rects.last!.containsEnd)

        for selection in rects {
            let index = layout.characterIndex(at: CGPoint(x: selection.rect.midX, y: selection.rect.midY))
            XCTAssertNotNil(index)
            XCTAssertTrue(NSLocationInRange(index!, match))
        }

        let bounds = layout.boundingRect(for: match)
        XCTAssertFalse(bounds.isNull)

        for selection in rects {
            XCTAssertTrue(bounds.insetBy(dx: -0.01, dy: -0.01).contains(selection.rect))
        }
    }

    func testClosestPositionRoundTripsThroughCarets() {
        let layout = layout(["Hello world", "Second line"], container: TextContainer(width: 300))

        for offset in 0...layout.textLength {
            let position = TextPosition(offset: offset)
            let caret = layout.caretRect(for: position)
            XCTAssertEqual(caret.width, 0)
            let found = layout.closestPosition(to: CGPoint(x: caret.minX, y: caret.midY))
            XCTAssertEqual(found.offset, offset, "offset \(offset)")
        }
    }

    func testSoftBreaksUseAffinity() {
        let layout = layout([longText], container: TextContainer(width: 120))
        let end = NSMaxRange(layout.line(at: 0).range)

        XCTAssertEqual(layout.lineIndex(containing: TextPosition(offset: end, affinity: .upstream)), 0)
        XCTAssertEqual(layout.lineIndex(containing: TextPosition(offset: end)), 1)
        XCTAssertLessThan(
            layout.caretRect(for: TextPosition(offset: end, affinity: .upstream)).minY,
            layout.caretRect(for: TextPosition(offset: end)).minY
        )
    }

    func testAttachmentsAreSingleCharacters() {
        let image = Image(.resolved(makeImage(size: CGSize(width: 24, height: 12))), size: .fixed(width: 24, height: 12))
        let layout = AttributedText {
            Paragraph {
                "A"
                image
                "B"
                Spacer(width: 16)
                "C"
            }
            .font(font)
        }
        .lower()
        .layout(in: TextContainer(width: 300))

        XCTAssertEqual(layout.textLength, 5)
        XCTAssertEqual(layout.text(in: NSRange(location: 1, length: 1)), "\u{FFFC}")
        XCTAssertEqual(layout.selectionRects(for: NSRange(location: 1, length: 1)).first?.rect.width ?? 0, 24, accuracy: 0.01)
        XCTAssertEqual(layout.selectionRects(for: NSRange(location: 3, length: 1)).first?.rect.width ?? 0, 16, accuracy: 0.01)
        XCTAssertEqual(layout.range(enclosing: 3, granularity: .character), NSRange(location: 3, length: 1))
    }

    func testGranularities() {
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"
        let first = "Hello brave world. Next one."
        let layout = layout([first, "x\(family)y"], container: TextContainer(width: 1000))
        let second = first.utf16.count + 1

        XCTAssertEqual(layout.range(enclosing: 8, granularity: .word), NSRange(location: 6, length: 5))
        XCTAssertEqual(layout.range(enclosing: 3, granularity: .sentence)?.location, 0)
        XCTAssertEqual(layout.range(enclosing: 3, granularity: .line), NSRange(location: 0, length: first.utf16.count))
        XCTAssertEqual(layout.range(enclosing: 3, granularity: .paragraph), NSRange(location: 0, length: first.utf16.count))
        XCTAssertEqual(
            layout.range(enclosing: second + 3, granularity: .character),
            NSRange(location: second + 1, length: family.utf16.count)
        )
        XCTAssertNil(layout.range(enclosing: layout.textLength, granularity: .word))
        XCTAssertNil(layout.range(enclosing: layout.textLength + 1, granularity: .paragraph))
    }

    func testTruncationHidesText() {
        let layout = layout([longText], container: TextContainer(width: 120, maximumNumberOfLines: 1))
        let visible = layout.visibleRange

        XCTAssertTrue(layout.isTruncated)
        XCTAssertTrue(layout.line(at: 0).isTruncated)
        XCTAssertLessThan(visible.length, layout.textLength)
        XCTAssertTrue(longText.hasPrefix(layout.text(in: visible)))
        XCTAssertNil(layout.lineIndex(containing: TextPosition(offset: NSMaxRange(visible) + 1)))
        XCTAssertNil(layout.range(enclosing: NSMaxRange(visible) + 1, granularity: .line))
        XCTAssertTrue(layout.selectionRects(for: NSRange(location: NSMaxRange(visible), length: 10)).isEmpty)
        XCTAssertTrue(layout.boundingRect(for: NSRange(location: NSMaxRange(visible), length: 10)).isNull)
    }

    func testLineQueriesByY() {
        let layout = layout([longText], container: TextContainer(width: 100))
        let second = layout.line(at: 1)

        XCTAssertEqual(layout.lineIndex(atY: second.frame.midY), 1)
        XCTAssertNil(layout.lineIndex(atY: -1))
        XCTAssertEqual(layout.lineIndexes(in: CGRect(x: 0, y: second.frame.midY, width: 1, height: 1)), 1..<2)
        XCTAssertEqual(layout.lineIndexes(in: .null), 0..<0)
        XCTAssertEqual(layout.lineIndexes(in: CGRect(x: 0, y: 0, width: 1, height: layout.size.height)), 0..<layout.lineCount)

        let window = CGRect(x: 0, y: second.frame.minY, width: 10, height: second.frame.height)
        let clipped = layout.selectionRects(for: NSRange(location: 0, length: layout.textLength), in: window)
        XCTAssertEqual(clipped.map(\.lineIndex), [1])
        XCTAssertTrue(layout.selectionRects(for: NSRange(location: 0, length: layout.textLength), in: .null).isEmpty)
    }

    func testNegativeInputsAreSafe() {
        let layout = layout(["Hello"], container: TextContainer(width: 300))

        XCTAssertNil(layout.lineIndex(containing: TextPosition(offset: -1)))
        XCTAssertNil(layout.range(enclosing: -1, granularity: .character))
        XCTAssertEqual(layout.caretRect(for: TextPosition(offset: -5)), layout.caretRect(for: TextPosition(offset: 0)))
        XCTAssertNil(layout.characterIndex(at: CGPoint(x: -10, y: -10)))
    }

    func testPreparedTextAnswersOffTheMainThread() async {
        let prepared = AttributedText {
            Paragraph { longText }
                .font(font)
        }
        .prepare(in: TextContainer(width: 150))

        let rects = await Task.detached {
            XCTAssertFalse(Thread.isMainThread)
            return prepared.layout.selectionRects(for: NSRange(location: 0, length: prepared.layout.textLength))
        }.value

        XCTAssertEqual(rects.count, prepared.layout.lineCount)
    }
}

private func makeImage(size: CGSize) -> PlatformImage {
    #if canImport(UIKit)
    UIGraphicsImageRenderer(size: size).image { _ in }
    #elseif canImport(AppKit)
    NSImage(size: size)
    #endif
}
