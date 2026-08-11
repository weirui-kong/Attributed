// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import AttributedCore
import AttributedTextKit
import XCTest

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

final class TextKitTests: XCTestCase {
    func testTextKitViewDisplaysRenderedContent() {
        let view = TextKitView()
        let rendered = Attributed.AttributedText {
            Attributed.Paragraph {
                "TextKit"
            }
        }.render()

        view.display(rendered)

        #if canImport(UIKit)
        XCTAssertEqual(view.textView.attributedText.string, "TextKit")
        #else
        XCTAssertNotNil(view.textLayoutManager)
        XCTAssertEqual(view.string, "TextKit")
        #endif
    }

    @MainActor
    func testTextKitViewDisplaysImageAttachment() {
        let image: PlatformImage

        #if canImport(UIKit)
        image = UIGraphicsImageRenderer(
            size: CGSize(width: 20, height: 10)
        ).image { _ in }
        #else
        image = PlatformImage(size: CGSize(width: 20, height: 10))
        #endif

        let rendered = Attributed.AttributedText {
            Attributed.Paragraph {
                Attributed.Image(image)
                    .size(.fixed(width: 20, height: 10))
            }
        }.render()
        let view = TextKitView()

        view.display(rendered)

        #if canImport(UIKit)
        let attributedString = view.textView.attributedText!
        #else
        let attributedString = view.attributedString()
        #endif

        XCTAssertNotNil(
            attributedString.attribute(
                .attachment,
                at: 0,
                effectiveRange: nil
            ) as? NSTextAttachment
        )
    }

    @MainActor
    func testTextKitViewHeightRespondsToWidth() {
        let rendered = Attributed.AttributedText {
            Attributed.Paragraph {
                String(repeating: "Width dependent text ", count: 20)
            }
            .font(.systemFont(ofSize: 17))
        }.render()
        let view = TextKitView()
        view.display(rendered)

        let narrowHeight = view.heightThatFits(width: 120)
        let wideHeight = view.heightThatFits(width: 480)

        XCTAssertGreaterThan(narrowHeight, wideHeight)
    }
}
