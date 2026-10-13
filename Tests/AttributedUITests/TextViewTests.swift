// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import AttributedCore
import AttributedEngineObjC
import AttributedViewObjC
import Foundation
import XCTest
@testable import AttributedUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

private typealias AttributedText = Attributed.AttributedText
private typealias Paragraph = Attributed.Paragraph
private typealias Text = Attributed.Text
private typealias Image = Attributed.Image

@MainActor
private final class RecordingDelegate: Attributed.TextViewDelegate {
    var events: [Attributed.InteractionEvent] = []
    var openRequests: [URL] = []

    func textView(_ textView: Attributed.TextView, didRecognize event: Attributed.InteractionEvent) {
        events.append(event)
    }

    func textView(
        _ textView: Attributed.TextView,
        shouldOpen url: URL,
        event: Attributed.InteractionEvent
    ) -> Bool {
        openRequests.append(url)
        return false
    }
}

@MainActor
final class TextViewTests: XCTestCase {
    func testPreparedTextFromABackgroundQueueIsShownAsIs() async {
        let prepared = await Task.detached {
            AttributedText {
                Paragraph {
                    "Prepared "
                    Text("off").onTap(value: 1)
                    " the main thread"
                }
                .font(.systemFont(ofSize: 20))
            }
            .prepare(in: Attributed.TextContainer(width: 400))
        }.value
        let textView = Attributed.TextView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        textView.setText(prepared)
        layoutNow(textView)

        XCTAssertTrue(textView.display.textLayout === prepared.layout.engine)
        XCTAssertEqual(textView.display.hitViews.count, 1)
        XCTAssertNotNil(textView.text)
    }

    func testDelegateReceivesValuesRangesAndLocations() {
        let url = URL(string: "https://example.com")!
        var ran = false
        let delegate = RecordingDelegate()
        let textView = Attributed.TextView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        textView.delegate = delegate
        textView.text = AttributedText {
            Paragraph {
                "Visit "
                Text("site").link(url)
                " "
                Text("hold").onLongPress(value: 7)
                Text("go").onTap { ran = true }
            }
            .font(.systemFont(ofSize: 24))
        }
        layoutNow(textView)

        for hitView in textView.display.hitViews {
            for binding in hitView.bindings {
                binding.trigger(atLocation: CGPoint(x: 1, y: 2))
            }
        }

        XCTAssertEqual(delegate.events.count, 3)
        let link = delegate.events.first { $0.value(as: URL.self) != nil }
        let hold = delegate.events.first { $0.value(as: Int.self) != nil }
        let closure = delegate.events.first { $0.value == nil }

        XCTAssertEqual(link?.value(as: URL.self), url)
        XCTAssertEqual(link?.gesture, .tap(count: 1))
        XCTAssertEqual(link?.range, NSRange(location: 6, length: 4))
        XCTAssertEqual(link?.text, "site")
        XCTAssertEqual(link?.rects.count, 1)
        XCTAssertEqual(link?.location.x ?? 0, (link?.rects.first?.minX ?? 0) + 1, accuracy: 0.001)

        XCTAssertEqual(hold?.value(as: Int.self), 7)
        XCTAssertEqual(hold?.gesture, .longPress(minimumDuration: 0.5))
        XCTAssertEqual(hold?.text, "hold")

        XCTAssertEqual(closure?.text, "go")
        XCTAssertTrue(ran)
        XCTAssertEqual(delegate.openRequests, [url])
    }

    func testMeasuresAndLoadsDeferredImages() {
        let image = makeImage(size: CGSize(width: 200, height: 100))
        var loads = 0
        let textView = Attributed.TextView(frame: CGRect(x: 0, y: 0, width: 300, height: 100))
        textView.text = AttributedText {
            Paragraph {
                "A"
                Image(.defer { loads += 1; return image }, size: .adaptive(maxWidth: 80))
            }
        }
        layoutNow(textView)

        let before = textView.measuredSize(forWidth: 300)
        XCTAssertEqual(loads, 0)
        XCTAssertGreaterThan(before.height, 0)

        let deadline = Date().addingTimeInterval(2)

        while loads == 0, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }

        layoutNow(textView)
        XCTAssertEqual(loads, 1)
        let frame = textView.textLayout?.engine.attachmentFrame(at: 0).frame
        XCTAssertEqual(frame?.size, CGSize(width: 80, height: 40))
        XCTAssertGreaterThanOrEqual(textView.measuredSize(forWidth: 300).height, 40)
    }

    func testPropertiesReachTheDisplay() {
        let textView = Attributed.TextView(frame: CGRect(x: 0, y: 0, width: 120, height: 200))
        textView.text = AttributedText {
            Paragraph { longText }
        }
        textView.maximumNumberOfLines = 2
        textView.truncationToken = "..."
        textView.lineHeightMode = .glyphBounds
        textView.isViewportRenderingEnabled = true
        textView.tileHeight = 64
        textView.appliesGradientToEmoji = true
        textView.rendersAsynchronously = true
        layoutNow(textView)

        XCTAssertEqual(textView.display.maximumNumberOfLines, 2)
        XCTAssertEqual(textView.display.truncationToken, "...")
        XCTAssertEqual(textView.display.lineHeightMode, .glyphBounds)
        XCTAssertTrue(textView.display.isViewportRenderingEnabled)
        XCTAssertEqual(textView.display.tileHeight, 64)
        XCTAssertTrue(textView.display.appliesGradientToColorGlyphs)
        XCTAssertTrue(textView.display.rendersAsynchronously)

        let layout = textView.textLayout
        XCTAssertEqual(layout?.lineCount, 2)
        XCTAssertEqual(layout?.isTruncated, true)
        XCTAssertEqual(layout?.line(at: 1).isTruncated, true)
    }

    func testNegativeLineLimitMeansUnlimited() {
        let textView = Attributed.TextView(frame: CGRect(x: 0, y: 0, width: 120, height: 200))
        textView.text = AttributedText {
            Paragraph { longText }
        }
        textView.maximumNumberOfLines = -3
        layoutNow(textView)

        XCTAssertEqual(textView.display.maximumNumberOfLines, 0)
        XCTAssertEqual(textView.textLayout?.isTruncated, false)
        XCTAssertGreaterThan(textView.textLayout?.lineCount ?? 0, 2)
    }

    func testClearingTheTextClearsTheLayoutAndLabel() {
        let textView = Attributed.TextView(frame: CGRect(x: 0, y: 0, width: 300, height: 100))
        textView.text = AttributedText {
            Paragraph { Text("tap").onTap(value: 1) }
        }
        layoutNow(textView)
        XCTAssertNotNil(textView.textLayout)
        XCTAssertEqual(spokenLabel(of: textView), "tap")

        textView.text = nil
        layoutNow(textView)

        XCTAssertNil(textView.textLayout)
        XCTAssertTrue(textView.display.hitViews.isEmpty)
        XCTAssertNil(spokenLabel(of: textView))
        XCTAssertEqual(textView.measuredSize(forWidth: 300), .zero)
    }

    func testAccessibilityLabelReadsImageLabels() {
        let image = makeImage(size: CGSize(width: 4, height: 4))
        let textView = Attributed.TextView(
            AttributedText {
                Paragraph {
                    "Rated "
                    Image(.resolved(image), size: .fixed(width: 4, height: 4), accessibilityLabel: "five stars")
                    Image(.resolved(image), size: .fixed(width: 4, height: 4))
                }
                Paragraph { "Done" }
            }
        )

        XCTAssertEqual(spokenLabel(of: textView), "Rated five stars\nDone")
        XCTAssertNotNil(textView.text)
    }

    func testMismatchedPreparedTextIsLaidOutAgain() {
        let prepared = AttributedText {
            Paragraph { longText }
        }
        .prepare(in: Attributed.TextContainer(width: 400))
        let textView = Attributed.TextView(frame: CGRect(x: 0, y: 0, width: 150, height: 200))
        textView.setText(prepared)
        layoutNow(textView)

        XCTAssertFalse(textView.display.textLayout === prepared.layout.engine)
        XCTAssertEqual(textView.textLayout?.engine.container.width, 150)
        XCTAssertGreaterThan(textView.textLayout?.lineCount ?? 0, prepared.layout.lineCount)

        // A prepared layout with other settings is not used either.
        let limited = AttributedText {
            Paragraph { longText }
        }
        .prepare(in: Attributed.TextContainer(width: 150, maximumNumberOfLines: 1))
        textView.setText(limited)
        layoutNow(textView)
        XCTAssertFalse(textView.display.textLayout === limited.layout.engine)
        XCTAssertEqual(textView.textLayout?.isTruncated, false)
    }

    func testMeasuringMatchesTheLayout() {
        let textView = Attributed.TextView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        textView.text = AttributedText {
            Paragraph { longText }
        }
        layoutNow(textView)
        let size = textView.measuredSize(forWidth: 200)
        let layoutSize = textView.textLayout?.size ?? .zero

        XCTAssertEqual(size.width, ceil(layoutSize.width))
        XCTAssertEqual(size.height, ceil(layoutSize.height))
        XCTAssertEqual(textView.intrinsicContentSize, size)
        #if canImport(UIKit)
        XCTAssertEqual(textView.sizeThatFits(CGSize(width: 200, height: 1)), size)
        #endif
        XCTAssertGreaterThan(textView.measuredSize(forWidth: 80).height, size.height)
    }

    func testReplacedTextNeverLoadsItsDeferredImages() {
        let image = makeImage(size: CGSize(width: 20, height: 20))
        var staleLoads = 0
        var currentLoads = 0
        let textView = Attributed.TextView(frame: CGRect(x: 0, y: 0, width: 300, height: 100))
        textView.text = AttributedText {
            Paragraph {
                Image(.defer { staleLoads += 1; return image }, size: .fixed(width: 20, height: 20))
            }
        }
        textView.text = AttributedText {
            Paragraph {
                Image(.defer { currentLoads += 1; return image }, size: .fixed(width: 20, height: 20))
            }
        }

        let deadline = Date().addingTimeInterval(2)

        while currentLoads == 0, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }

        XCTAssertEqual(currentLoads, 1)
        XCTAssertEqual(staleLoads, 0)
    }

    func testEventsForWrappedInteractionsCarryEveryRect() {
        let delegate = RecordingDelegate()
        let textView = Attributed.TextView(frame: CGRect(x: 0, y: 0, width: 140, height: 400))
        textView.delegate = delegate
        textView.text = AttributedText {
            Paragraph {
                Text(longText).onTap(value: "long")
            }
        }
        layoutNow(textView)
        textView.display.hitViews.first?.bindings.first?.trigger(atLocation: .zero)

        let event = delegate.events.first
        XCTAssertEqual(event?.rects.count, textView.textLayout?.lineCount)
        XCTAssertEqual(event?.range, NSRange(location: 0, length: longText.utf16.count))
        XCTAssertEqual(event?.text, longText)
        XCTAssertTrue(delegate.openRequests.isEmpty)
    }

    func testEventsUseTheTextViewsCoordinates() {
        let delegate = RecordingDelegate()
        let container = PlatformView(frame: CGRect(x: 0, y: 0, width: 500, height: 500))
        let textView = Attributed.TextView(frame: CGRect(x: 30, y: 40, width: 300, height: 100))
        container.addSubview(textView)
        textView.delegate = delegate
        textView.text = AttributedText {
            Paragraph {
                "Go "
                Text("here").onTap(value: 1)
            }
        }
        layoutNow(textView)

        let hitView = textView.display.hitViews.first
        hitView?.bindings.first?.trigger(atLocation: CGPoint(x: 2, y: 3))
        let event = delegate.events.first
        let rect = textView.textLayout?.selectionRects(for: NSRange(location: 3, length: 4)).first?.rect

        XCTAssertEqual(event?.rects.first?.minX ?? 0, rect?.minX ?? -1, accuracy: 0.5)
        XCTAssertEqual(event?.location.x ?? 0, (hitView?.frame.minX ?? 0) + 2, accuracy: 0.001)
        XCTAssertEqual(event?.location.y ?? 0, (hitView?.frame.minY ?? 0) + 3, accuracy: 0.001)
    }
}

private let longText = "The quick brown fox jumps over the lazy dog and keeps running across the field."

@MainActor
private func spokenLabel(of view: Attributed.TextView) -> String? {
    #if canImport(UIKit)
    view.accessibilityLabel
    #elseif canImport(AppKit)
    view.accessibilityLabel()
    #endif
}

@MainActor
private func layoutNow(_ view: Attributed.TextView) {
    #if canImport(UIKit)
    view.layoutIfNeeded()
    #elseif canImport(AppKit)
    view.layoutSubtreeIfNeeded()
    #endif
}

private func makeImage(size: CGSize) -> PlatformImage {
    #if canImport(UIKit)
    UIGraphicsImageRenderer(size: size).image { context in
        UIColor.red.setFill()
        context.fill(CGRect(origin: .zero, size: size))
    }
    #elseif canImport(AppKit)
    NSImage(size: size, flipped: false) { rect in
        NSColor.red.setFill()
        rect.fill()
        return true
    }
    #endif
}
