// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import Foundation
import XCTest
@testable import AttributedCore

private typealias AttributedBlock = Attributed.AttributedBlock
private typealias RenderContext = Attributed.RenderContext
private typealias NodeRenderResult = Attributed.NodeRenderResult
private typealias AttributedText = Attributed.AttributedText
private typealias TextAttributes = Attributed.TextAttributes
private typealias ParagraphAttributes = Attributed.ParagraphAttributes
private typealias Paragraph = Attributed.Paragraph
private typealias Text = Attributed.Text
private typealias Link = Attributed.Link
private typealias InteractionID = Attributed.InteractionID

private struct TestBlock: AttributedBlock {
    func render(context: RenderContext) -> NodeRenderResult {
        NodeRenderResult(attributedString: NSAttributedString())
    }
}

final class CoreTests: XCTestCase {
    func testPlatformFontCanBeCreated() {
        let font = PlatformFont.systemFont(ofSize: 16)

        XCTAssertGreaterThan(font.pointSize, 0)
    }

    func testDocumentBuilderSupportsConditionalsAndLoops() {
        let includeExtra = true
        let document = AttributedText {
            TestBlock()

            if includeExtra {
                TestBlock()
            }

            for _ in 0..<2 {
                TestBlock()
            }
        }

        XCTAssertEqual(document.children.count, 4)
    }

    func testTextAttributesMergeAndConvertAllSupportedValues() {
        var parent = TextAttributes()
        parent.font = .systemFont(ofSize: 12)
        parent.foregroundColor = .black
        parent.kern = 1

        var child = TextAttributes()
        child.font = .boldSystemFont(ofSize: 16)
        child.underlineStyle = .single
        child.underlineColor = .blue

        let merged = parent.merging(child)
        let attributes = merged.nsAttributes

        XCTAssertEqual((attributes[.font] as? PlatformFont)?.pointSize, 16)
        XCTAssertNotNil(attributes[.foregroundColor] as? PlatformColor)
        XCTAssertEqual(attributes[.kern] as? CGFloat, 1)
        XCTAssertEqual(attributes[.underlineStyle] as? Int, NSUnderlineStyle.single.rawValue)
        XCTAssertNotNil(attributes[.underlineColor] as? PlatformColor)
    }

    func testParagraphAttributesMergeAndCreateStyle() {
        var parent = ParagraphAttributes()
        parent.alignment = .left
        parent.lineSpacing = 4

        var child = ParagraphAttributes()
        child.alignment = .center
        child.baseWritingDirection = .rightToLeft
        child.paragraphSpacing = 8

        let style = parent.merging(child).makeNSParagraphStyle()

        XCTAssertEqual(style.alignment, .center)
        XCTAssertEqual(style.baseWritingDirection, .rightToLeft)
        XCTAssertEqual(style.lineSpacing, 4)
        XCTAssertEqual(style.paragraphSpacing, 8)
    }

    func testRenderingInheritsAttributesAndRemovesFinalParagraphTerminator() {
        let content = AttributedText {
            Paragraph {
                "Hello "
                Text("World").font(.boldSystemFont(ofSize: 16))
            }
            .font(.systemFont(ofSize: 12))
            .foregroundColor(.black)
            .lineSpacing(4)

            Paragraph {
                "Second"
            }
            .alignment(.center)
        }

        let rendered = content.render().attributedString

        XCTAssertEqual(rendered.string, "Hello World\nSecond")
        XCTAssertEqual(
            (rendered.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont)?.pointSize,
            12
        )
        XCTAssertEqual(
            (rendered.attribute(.font, at: 6, effectiveRange: nil) as? PlatformFont)?.pointSize,
            16
        )
        XCTAssertEqual(
            (rendered.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.lineSpacing,
            4
        )
        XCTAssertEqual(
            (rendered.attribute(.paragraphStyle, at: rendered.length - 1, effectiveRange: nil) as? NSParagraphStyle)?.alignment,
            .center
        )
    }

    func testLinkRegistersInteractionAndEmitsStandardURLAttribute() {
        let url = URL(string: "https://example.com")!
        let rendered = AttributedText {
            Paragraph {
                Link("Example", url: url)
            }
        }.render()

        let id = rendered.attributedString.attribute(
            .attributedInteractionID,
            at: 0,
            effectiveRange: nil
        ) as? InteractionID

        XCTAssertNotNil(id)
        XCTAssertEqual(
            rendered.attributedString.attribute(.link, at: 0, effectiveRange: nil) as? URL,
            url
        )

        guard let id, case let .url(registeredURL)? = rendered.interaction(for: id) else {
            return XCTFail("Expected the rendered link to be registered.")
        }

        XCTAssertEqual(registeredURL, url)
    }
}
