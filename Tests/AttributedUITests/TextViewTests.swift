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
