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

private let longText = "The quick brown fox jumps over the lazy dog and keeps running across the field."

final class TextLayoutTests: XCTestCase {
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
