// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import Attributed
import SwiftUI
import XCTest

final class AttributedTests: XCTestCase {
    func testFacadeDoesNotConflictWithSwiftUIText() {
        _ = Text("SwiftUI")

        let rendered = AAttributedText {
            AParagraph {
                AText("Attributed")
            }
        }.render()

        XCTAssertEqual(rendered.attributedString.string, "Attributed")
    }
}
