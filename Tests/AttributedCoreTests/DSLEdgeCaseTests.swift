// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import Foundation
import AttributedEngineObjC
import XCTest
@testable import AttributedCore

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

private typealias AttributedText = Attributed.AttributedText
private typealias Group = Attributed.Group
private typealias Image = Attributed.Image
private typealias Paragraph = Attributed.Paragraph
private typealias Spacer = Attributed.Spacer
private typealias Text = Attributed.Text
private typealias TextContainer = Attributed.TextContainer

final class DSLEdgeCaseTests: XCTestCase {
    func testTheLastModifierOfAKindWins() {
        let document = AttributedText {
            Paragraph {
                Text("a")
                    .font(.systemFont(ofSize: 10))
                    .font(.systemFont(ofSize: 20))
                    .kern(1)
                    .kern(3)
                    .underline(.double, color: .red)
                    .underline()
            }
        }
        .lower()
        .document

        XCTAssertEqual(
            opsDump(document),
            """
            base paragraph{} text{fg=c0}
            P paragraph{} text{}
              SPAN text{font=f0 kern=3 underline=single,solid}
                "a"
              END
            /P
            """
        )
        // The replaced font and color are never registered.
        XCTAssertEqual(document.fontCount, 1)
        XCTAssertEqual(document.colorCount, 1)
        XCTAssertEqual(document.font(Attributed.IR.FontRef(index: 0)).pointSize, 20)
    }

    func testParagraphTextModifiersStyleTheWholeParagraph() {
        let document = AttributedText {
            Paragraph { "body" }
                .backgroundColor(.yellow)
                .kern(2)
                .alignment(.justified)
                .lineSpacing(3)
                .paragraphSpacing(5)
                .baseWritingDirection(.leftToRight)
        }
        .lower()
        .document

        XCTAssertEqual(
            opsDump(document),
            """
            base paragraph{} text{fg=c0}
            P paragraph{align=justified direction=leftToRight lineSpacing=3 paragraphSpacing=5} text{bg=c1 kern=2}
              "body"
            /P
            """
        )
    }

    func testEmptyTextLowersAndLaysOutToNothing() {
        let lowered = AttributedText {}.lower()
        let layout = lowered.layout(in: TextContainer(width: 200))

        XCTAssertEqual(opsDump(lowered.document), "base paragraph{} text{fg=c0}")
        XCTAssertEqual(layout.lineCount, 0)
        XCTAssertEqual(layout.size, .zero)
        XCTAssertEqual(layout.textLength, 0)
        XCTAssertEqual(layout.visibleRange, NSRange(location: 0, length: 0))
    }

    func testEmptyParagraphsStillTakeALine() {
        let layout = AttributedText {
            Paragraph {}
            Paragraph { "" }
        }
        .lower()
        .layout(in: TextContainer(width: 200))

        XCTAssertEqual(layout.lineCount, 2)
        XCTAssertEqual(layout.textLength, 1)
        XCTAssertGreaterThan(layout.size.height, 0)
    }

    func testBuilderBranchesThatProduceNothing() {
        let showA = false
        let items: [String] = []
        let document = AttributedText {
            if showA {
                Paragraph { "A" }
            }

            for item in items {
                Paragraph { item }
            }

            Paragraph {
                if showA {
                    "hidden"
                } else {
                    "shown"
                }

                for item in items {
                    item
                }
            }
        }
        .lower()
        .document

        XCTAssertEqual(
            opsDump(document),
            """
            base paragraph{} text{fg=c0}
            P paragraph{} text{}
              "shown"
            /P
            """
        )
    }

    func testUnicodeSurvivesLowering() {
        let text = "e\u{301} \u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467} 中文 שלום \u{0}"
        let layout = AttributedText {
            Paragraph { text }
        }
        .lower()
        .layout(in: TextContainer(width: 1000))

        XCTAssertEqual(layout.textLength, text.utf16.count)
        XCTAssertEqual(layout.text(in: NSRange(location: 0, length: layout.textLength)), text)
    }

    func testManyParagraphsKeepTheirOffsets() {
        let count = 500
        let layout = AttributedText {
            for index in 0..<count {
                Paragraph { "Paragraph \(index)" }
            }
        }
        .lower()
        .layout(in: TextContainer(width: 1000))
        let expectedLength = (0..<count).map { "Paragraph \($0)".utf16.count }.reduce(0, +) + count - 1

        XCTAssertEqual(layout.lineCount, count)
        XCTAssertEqual(layout.textLength, expectedLength)
        XCTAssertEqual(layout.text(in: layout.line(at: count - 1).range), "Paragraph \(count - 1)")
        XCTAssertEqual(layout.range(enclosing: layout.textLength - 1, granularity: .paragraph), layout.line(at: count - 1).range)
    }

    @MainActor
    func testALinkInsideATappableTextWinsItsTap() {
        let url = URL(string: "https://example.com")!
        let lowered = AttributedText {
            Paragraph {
                "Read "
                Text("more").link(url)
            }
            .onTap(value: "paragraph")
            .onLongPress(value: "press")
        }
        .lower()

        let engine = lowered.document.engine
        let layout = lowered.layout(in: TextContainer(width: 400)).engine
        var setsByText: [String: [UInt32]] = [:]

        for index in 0..<layout.hitRegionCount {
            let region = layout.hitRegion(at: index)
            let ids = layout.interactions(inSet: region.interactionSet).map(\.uint32Value)
            let range = engine.range(forInteraction: ids[0])
            setsByText[engine.text(in: range)] = ids
        }

        // Outer modifiers register first: i0 is the long press, i1 the
        // paragraph tap, i2 the link. "more" keeps its own tap and the long
        // press; the paragraph tap is shadowed there.
        XCTAssertEqual(setsByText["more"], [2, 0])
        XCTAssertEqual(setsByText["Read more"], [1, 0])

        guard case let .value(value) = lowered.interaction(for: Attributed.InteractionID(rawValue: 2)) else {
            return XCTFail("Expected the link value.")
        }

        XCTAssertEqual(value as? URL, url)
    }

    func testAttachmentAlignmentsLower() {
        let image = makeImage(size: CGSize(width: 8, height: 8))
        let document = AttributedText {
            Paragraph {
                Image(.resolved(image), size: .fixed(width: 8, height: 8)).alignment(.top)
                Image(.resolved(image), size: .fixed(width: 8, height: 8)).alignment(.bottom)
                Image(.resolved(image), size: .adaptive(maxWidth: 5, maxHeight: 6))
                Spacer(width: 0)
            }
        }
        .lower()
        .document

        XCTAssertEqual(
            opsDump(document),
            """
            base paragraph{} text{fg=c0}
            P paragraph{} text{}
              ATTACH a0 image size=fixed(8x8) content=8x8 align=top
              ATTACH a1 image size=fixed(8x8) content=8x8 align=bottom
              ATTACH a2 image size=adaptive(5x6) content=8x8 align=baseline
              ATTACH a3 spacer width=0 height=inferred
            /P
            """
        )
    }

    func testCustomGradientPoints() {
        let gradient = Attributed.TextGradient(
            colors: [.red, .green, .blue],
            locations: [0, 0.5, 1],
            startPoint: Attributed.GradientPoint(x: 0.25, y: 0.75),
            endPoint: .bottomRight,
            scope: .document
        )
        let document = AttributedText {
            Paragraph { Text("g").gradient(gradient) }
        }
        .lower()
        .document

        XCTAssertTrue(
            opsDump(document).hasSuffix(
                "g0 = linear (0.25,0.75)->(1,1) [c1 c2 c3] @[0 0.5 1] scope=document"
            ),
            opsDump(document)
        )
    }

    func testUnderlineRadiusIsKeptAsGiven() {
        let style = Attributed.UnderlineStyle(thickness: 2, corners: .radius(10))
        let document = AttributedText {
            Paragraph { Text("r").underline(style) }
        }
        .lower()
        .document

        // Clamping to half the thickness happens when drawing.
        XCTAssertTrue(opsDump(document).contains("underline=single,solid,2,radius=10"), opsDump(document))
    }

    func testLoweringIsRepeatable() {
        let text = AttributedText {
            Paragraph {
                Text("a").foregroundColor(.red)
                Text("b").gradient(Attributed.TextGradient(colors: [.red, .blue]))
            }
        }

        XCTAssertEqual(opsDump(text.lower().document), opsDump(text.lower().document))
    }
}

private func opsDump(_ document: Attributed.IR.Document) -> String {
    document.dump()
        .components(separatedBy: "\n---")[0]
}

private func makeImage(size: CGSize) -> PlatformImage {
    #if canImport(UIKit)
    UIGraphicsImageRenderer(size: size).image { _ in }
    #elseif canImport(AppKit)
    NSImage(size: size)
    #endif
}
