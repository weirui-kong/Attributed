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

private typealias AttributedBlock = Attributed.AttributedBlock
private typealias AttributedText = Attributed.AttributedText
private typealias Paragraph = Attributed.Paragraph
private typealias Text = Attributed.Text
private typealias Image = Attributed.Image
private typealias Group = Attributed.Group
private typealias Spacer = Attributed.Spacer
private typealias IR = Attributed.IR

private struct EmptyBlock: AttributedBlock {
    func lower(into builder: inout IR.Builder) {}
}

private struct QuoteBlock: AttributedBlock {
    let text: String

    func lower(into builder: inout IR.Builder) {
        var style = IR.ParagraphStyle()
        style.alignment = .center

        builder.paragraph(style) { builder in
            builder.text("“")
            builder.text(text)
            builder.text("”")
        }
    }
}

final class LoweringTests: XCTestCase {
    func testSpacersLowerToAttachmentsWithoutImages() {
        let lowered = AttributedText {
            Paragraph {
                "a"
                Spacer(width: 12)
                Text("b").onTap(value: 1)
                Spacer(width: 4, height: 30)
            }
        }
        .lower()

        XCTAssertEqual(
            opsDump(lowered.document),
            """
            base paragraph{} text{fg=c0}
            P paragraph{} text{}
              "a"
              ATTACH a0 spacer width=12 height=inferred
              SPAN i0 text{}
                "b"
              END
              ATTACH a1 spacer width=4 height=30
            /P
            i0 = tap(1)
            """
        )
        XCTAssertNil(lowered.imageSource(for: Attributed.AttachmentID(rawValue: 0)))
        XCTAssertNil(lowered.imageSource(for: Attributed.AttachmentID(rawValue: 1)))
        // The spacer counts as one U+FFFC before "b".
        XCTAssertEqual(lowered.document.engine.range(forInteraction: 0), NSRange(location: 2, length: 1))
    }

    func testDocumentBuilderSupportsConditionalsAndLoops() {
        let includeExtra = true
        let document = AttributedText {
            QuoteBlock(text: "a")

            if includeExtra {
                QuoteBlock(text: "b")
            }

            for index in 0..<2 {
                QuoteBlock(text: "\(index)")
            }
        }

        XCTAssertEqual(
            opsDump(document.lower().document)
                .components(separatedBy: "\n")
                .filter { $0 == "/P" }
                .count,
            4
        )
    }

    func testParagraphsAndSpansLowerToScopedOps() {
        let lowered = AttributedText {
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
        }.lower()

        XCTAssertEqual(
            opsDump(lowered.document),
            """
            base paragraph{} text{fg=c0}
            P paragraph{lineSpacing=4} text{font=f0 fg=c1}
              "Hello "
              SPAN text{font=f1}
                "World"
              END
            /P
            P paragraph{align=center} text{}
              "Second"
            /P
            """
        )
        XCTAssertEqual(
            (0..<lowered.document.fontCount).map {
                lowered.document.font(IR.FontRef(index: Int32($0))).pointSize
            },
            [12, 16]
        )
    }

    func testRootUsesSemanticDefaultForegroundColor() {
        let document = AttributedText {
            Paragraph { "Default color" }
        }.lower().document

        XCTAssertTrue(opsDump(document).hasPrefix("base paragraph{} text{fg=c0}\n"))

        let color = document.color(IR.ColorRef(index: 0))
        #if canImport(UIKit)
        XCTAssertTrue(color.isEqual(PlatformColor.label))
        #elseif canImport(AppKit)
        XCTAssertTrue(color.isEqual(PlatformColor.labelColor))
        #endif
    }

    func testResourcesAreDeduplicated() {
        let font = PlatformFont.systemFont(ofSize: 14)
        let document = AttributedText {
            Paragraph {
                Text("a").font(font).foregroundColor(.red)
                Text("b").font(font).foregroundColor(.red)
            }
            .font(font)
        }.lower().document

        XCTAssertEqual(document.fontCount, 1)
        XCTAssertEqual(document.colorCount, 2)
    }

    func testUnstyledTextAndEmptyStringsDoNotEmitExtraOps() {
        let document = AttributedText {
            Paragraph {
                "plain"
                ""
                Text("")
            }
            EmptyBlock()
        }.lower().document

        XCTAssertEqual(
            opsDump(document),
            """
            base paragraph{} text{fg=c0}
            P paragraph{} text{}
              "plain"
            /P
            """
        )
    }

    func testTextStyleModifiersLowerToPrimitives() {
        let document = AttributedText {
            Paragraph {
                Text("styled")
                    .kern(1.5)
                    .baselineOffset(-2)
                    .backgroundColor(.yellow)
                    .underline(.double, color: .blue)
            }
            .baseWritingDirection(.rightToLeft)
            .paragraphSpacing(8)
        }.lower().document

        XCTAssertEqual(
            opsDump(document),
            """
            base paragraph{} text{fg=c0}
            P paragraph{direction=rightToLeft paragraphSpacing=8} text{}
              SPAN text{bg=c1 kern=1.5 baseline=-2 underline=double,solid underlineFill=c2}
                "styled"
              END
            /P
            """
        )
    }

    @MainActor
    func testTextLinkRegistersURLInteraction() {
        let url = URL(string: "https://example.com")!
        let lowered = AttributedText {
            Paragraph {
                Text("Example")
                    .link(url)
                    .underline()
            }
        }.lower()

        XCTAssertEqual(
            opsDump(lowered.document),
            """
            base paragraph{} text{fg=c0}
            P paragraph{} text{}
              SPAN i0 text{underline=single,solid}
                "Example"
              END
            /P
            i0 = tap(1)
            """
        )

        guard case let .value(value) = lowered.interaction(
            for: Attributed.InteractionID(rawValue: 0)
        ) else {
            return XCTFail("Expected a value interaction.")
        }

        XCTAssertEqual(value as? URL, url)
        XCTAssertEqual(lowered.gesture(for: Attributed.InteractionID(rawValue: 0)), .tap(count: 1))
    }

    @MainActor
    func testOnTapWrapsInlineAndBlockNodes() {
        var taps: [String] = []
        let lowered = AttributedText {
            Paragraph {
                Text("text").onTap { taps.append("text") }
                Image(
                    .resolved(makeImage(size: CGSize(width: 4, height: 4))),
                    size: .fixed(width: 4, height: 4)
                )
                    .onTap { taps.append("image") }
            }
            .onTap { taps.append("paragraph") }
        }.lower()

        XCTAssertEqual(
            opsDump(lowered.document),
            """
            base paragraph{} text{fg=c0}
            SPAN i0 text{}
              P paragraph{} text{}
                SPAN i1 text{}
                  "text"
                END
                SPAN i2 text{}
                  ATTACH a0 image size=fixed(4x4) content=4x4 align=baseline
                END
              /P
            END
            i0 = tap(1)
            i1 = tap(1)
            i2 = tap(1)
            """
        )

        for rawValue in [UInt32(2), 1, 0] {
            guard case let .action(action) = lowered.interaction(
                for: Attributed.InteractionID(rawValue: rawValue)
            ) else {
                return XCTFail("Expected an action interaction.")
            }

            action()
        }

        XCTAssertEqual(taps, ["image", "text", "paragraph"])
    }

    @MainActor
    func testGesturesCarryCountsDurationsAndValues() {
        let url = URL(string: "https://example.com/item")!
        var ran = false
        let lowered = AttributedText {
            Paragraph {
                Text("double").onTap(count: 2, value: url)
                Text("hold").onLongPress(minimumDuration: 1.5, value: 42)
                Text("closure").onTap { ran = true }
            }
        }.lower()

        XCTAssertEqual(
            opsDump(lowered.document).components(separatedBy: "\n").suffix(3),
            ["i0 = tap(2)", "i1 = longPress(1.5)", "i2 = tap(1)"]
        )
        XCTAssertEqual(lowered.gesture(for: Attributed.InteractionID(rawValue: 0)), .tap(count: 2))
        XCTAssertEqual(
            lowered.gesture(for: Attributed.InteractionID(rawValue: 1)),
            .longPress(minimumDuration: 1.5)
        )

        guard case let .value(first) = lowered.interaction(for: Attributed.InteractionID(rawValue: 0)),
              case let .value(second) = lowered.interaction(for: Attributed.InteractionID(rawValue: 1)),
              case let .action(action) = lowered.interaction(for: Attributed.InteractionID(rawValue: 2))
        else {
            return XCTFail("Expected two values and one action.")
        }

        XCTAssertEqual(first as? URL, url)
        XCTAssertEqual(second as? Int, 42)
        action()
        XCTAssertTrue(ran)
    }

    @MainActor
    func testImageSourcesSelectTheirPipelines() {
        let image = makeImage(size: CGSize(width: 40, height: 20))
        let deferred = makeImage(size: CGSize(width: 30, height: 30))
        let lowered = AttributedText {
            Paragraph {
                "Before"
                Image(
                    .resolved(image),
                    size: .fixed(width: 16, height: 12),
                    accessibilityLabel: "Local"
                )
                .alignment(.center)
                Image(.resolved(image), size: .adaptive(maxHeight: 10))
                Image(
                    .defer { deferred },
                    size: .adaptive(maxWidth: 200),
                    accessibilityLabel: ""
                )
                .alignment(.offset(-1.5))
            }
        }.lower()

        XCTAssertEqual(
            opsDump(lowered.document),
            """
            base paragraph{} text{fg=c0}
            P paragraph{} text{}
              "Before"
              ATTACH a0 image size=fixed(16x12) content=40x20 align=center label="Local"
              ATTACH a1 image size=adaptive(-x10) content=40x20 align=baseline
              ATTACH a2 asyncImage size=adaptive(200x-) align=offset(-1.5)
            /P
            """
        )

        guard case let .resolved(resolvedImage) = lowered.imageSource(
            for: Attributed.AttachmentID(rawValue: 0)
        ) else {
            return XCTFail("Expected a resolved image source.")
        }

        XCTAssertTrue(resolvedImage === image)

        guard case let .defer(load) = lowered.imageSource(
            for: Attributed.AttachmentID(rawValue: 2)
        ) else {
            return XCTFail("Expected a deferred image source.")
        }

        XCTAssertTrue(load() === deferred)
    }

    func testEqualGradientsShareOneRef() {
        let sunset = Attributed.TextGradient(colors: [.red, .orange])
        let lowered = AttributedText {
            Paragraph {
                Text("Warm").gradient(sunset)
                " plain "
                Text("glow").gradient(
                    Attributed.TextGradient(colors: [.red, .orange])
                )
                Text(" line").gradient(
                    Attributed.TextGradient(
                        colors: [.red, .orange],
                        locations: [0, 0.25],
                        startPoint: .top,
                        endPoint: .bottom,
                        scope: .line
                    )
                )
            }
        }.lower()

        XCTAssertEqual(
            opsDump(lowered.document),
            """
            base paragraph{} text{fg=c0}
            P paragraph{} text{}
              SPAN text{fg=g0}
                "Warm"
              END
              " plain "
              SPAN text{fg=g0}
                "glow"
              END
              SPAN text{fg=g1}
                " line"
              END
            /P
            g0 = linear (0,0.5)->(1,0.5) [c1 c2] scope=paragraph
            g1 = linear (0.5,0)->(0.5,1) [c1 c2] @[0 0.25] scope=line
            """
        )
    }

    func testForegroundColorAndGradientReplaceEachOther() {
        let sunset = Attributed.TextGradient(colors: [.red, .orange])
        let document = AttributedText {
            Paragraph {
                Text("color wins").gradient(sunset).foregroundColor(.blue)
                Text("gradient wins").foregroundColor(.blue).gradient(sunset)
            }
        }.lower().document

        XCTAssertEqual(
            opsDump(document),
            """
            base paragraph{} text{fg=c0}
            P paragraph{} text{}
              SPAN text{fg=c1}
                "color wins"
              END
              SPAN text{fg=g0}
                "gradient wins"
              END
            /P
            g0 = linear (0,0.5)->(1,0.5) [c2 c3] scope=paragraph
            """
        )
    }

    func testUnderlinesAreDecorationsWithOptionalFill() {
        let sunset = Attributed.TextGradient(colors: [.red, .orange])
        let document = AttributedText {
            Paragraph {
                Text("follows foreground").gradient(sunset).underline()
                Text("own gradient").underline(
                    Attributed.UnderlineStyle(pattern: .dash, thickness: 2),
                    gradient: sunset
                )
                Text("own color").underline(.double, color: .blue)
                Text("capsule").underline(
                    Attributed.UnderlineStyle(pattern: .dot, corners: .capsule)
                )
                Text("radius").underline(
                    Attributed.UnderlineStyle(thickness: 4, corners: .radius(1.5))
                )
            }
        }.lower().document

        XCTAssertEqual(
            opsDump(document),
            """
            base paragraph{} text{fg=c0}
            P paragraph{} text{}
              SPAN text{fg=g0 underline=single,solid}
                "follows foreground"
              END
              SPAN text{underline=single,dash,2 underlineFill=g0}
                "own gradient"
              END
              SPAN text{underline=double,solid underlineFill=c3}
                "own color"
              END
              SPAN text{underline=single,dot,capsule}
                "capsule"
              END
              SPAN text{underline=single,solid,4,radius=1.5}
                "radius"
              END
            /P
            g0 = linear (0,0.5)->(1,0.5) [c1 c2] scope=paragraph
            """
        )
    }

    func testGroupsAddNothingOfTheirOwn() {
        let document = AttributedText {
            Group {
                Paragraph {
                    Group {
                        "one "
                        Text("two").kern(1)
                    }
                }
                Paragraph { "three" }
            }
        }.lower().document

        XCTAssertEqual(
            opsDump(document),
            """
            base paragraph{} text{fg=c0}
            P paragraph{} text{}
              "one "
              SPAN text{kern=1}
                "two"
              END
            /P
            P paragraph{} text{}
              "three"
            /P
            """
        )
    }

    @MainActor
    func testGestureOnGroupCoversAllChildren() {
        let lowered = AttributedText {
            Paragraph {
                "Before "
                Group {
                    Text("several ").font(.boldSystemFont(ofSize: 14))
                    Text("nodes")
                }
                .onTap(value: "group")
            }
            Group {
                Paragraph { "First" }
                Paragraph { "Second" }
            }
            .onLongPress(value: 2)
        }.lower()

        XCTAssertEqual(
            opsDump(lowered.document),
            """
            base paragraph{} text{fg=c0}
            P paragraph{} text{}
              "Before "
              SPAN i0 text{}
                SPAN text{font=f0}
                  "several "
                END
                "nodes"
              END
            /P
            SPAN i1 text{}
              P paragraph{} text{}
                "First"
              /P
              P paragraph{} text{}
                "Second"
              /P
            END
            i0 = tap(1)
            i1 = longPress(0.5)
            """
        )

        let engine = lowered.document.engine
        XCTAssertEqual(engine.range(forInteraction: 0), NSRange(location: 7, length: 13))
        XCTAssertEqual(engine.text(in: engine.range(forInteraction: 0)), "several nodes")
        XCTAssertEqual(engine.text(in: engine.range(forInteraction: 1)), "First\nSecond")
    }

    func testCustomBlocksUseThePublicBuilder() {
        let document = AttributedText {
            QuoteBlock(text: "quote")
        }.lower().document

        XCTAssertEqual(
            opsDump(document),
            """
            base paragraph{} text{fg=c0}
            P paragraph{align=center} text{}
              "“"
              "quote"
              "”"
            /P
            """
        )
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
