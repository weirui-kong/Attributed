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
private typealias Paragraph = Attributed.Paragraph
private typealias Text = Attributed.Text
private typealias TextContainer = Attributed.TextContainer
private typealias Spacer = Attributed.Spacer

private let longText = "The quick brown fox jumps over the lazy dog and keeps running across the field."

final class TextLayoutTests: XCTestCase {
    func testSpacerReservesWidthAndKeepsTheLineHeight() {
        let font = PlatformFont.systemFont(ofSize: 16)
        let unbounded = TextContainer(width: .infinity)
        func layout(@Attributed.AttributedInlineBuilder _ content: () -> [any Attributed.AttributedInline]) -> Attributed.TextLayout {
            let inline = content()
            return AttributedText {
                Paragraph {
                    for node in inline {
                        node
                    }
                }
                .font(font)
            }
            .lower()
            .layout(in: unbounded)
        }

        let plain = layout { "AB" }
        let spaced = layout {
            "A"
            Spacer(width: 20)
            "B"
        }
        let tall = layout {
            "A"
            Spacer(width: 20, height: 60)
            "B"
        }
        let alone = AttributedText {
            Paragraph { Spacer(width: 30) }.font(font)
        }
        .lower()
        .layout(in: unbounded)

        XCTAssertEqual(spaced.size.width, plain.size.width + 20, accuracy: 0.01)
        XCTAssertEqual(spaced.size.height, plain.size.height, accuracy: 0.01)
        XCTAssertGreaterThan(tall.size.height, 60)
        XCTAssertEqual(alone.size.width, 30, accuracy: 0.01)
        XCTAssertEqual(alone.size.height, plain.size.height, accuracy: 0.01)
    }

    func testLayoutMeasuresWrappedText() {
        let document = AttributedText {
            Paragraph { longText }
                .font(.systemFont(ofSize: 16))
        }.lower().document

        let narrow = document.layout(in: TextContainer(width: 120))
        let wide = document.layout(in: TextContainer(width: 2000))

        XCTAssertGreaterThan(narrow.lineCount, 1)
        XCTAssertEqual(wide.lineCount, 1)
        XCTAssertLessThanOrEqual(narrow.size.width, 120)
        XCTAssertGreaterThan(narrow.size.height, wide.size.height)
        XCTAssertFalse(narrow.isTruncated)
    }

    func testContainerLimitsTruncate() {
        let document = AttributedText {
            Paragraph { longText }
        }.lower().document

        let layout = document.layout(
            in: TextContainer(width: 120, maximumNumberOfLines: 2, truncationToken: "...")
        )

        XCTAssertEqual(layout.lineCount, 2)
        XCTAssertTrue(layout.isTruncated)
    }

    func testLayoutRunsOffTheMainThread() async {
        let document = AttributedText {
            Paragraph { longText }
        }.lower().document

        let size = await Task.detached {
            XCTAssertFalse(Thread.isMainThread)
            return document.layout(in: TextContainer(width: 200)).size
        }.value

        XCTAssertGreaterThan(size.height, 0)
    }
}
