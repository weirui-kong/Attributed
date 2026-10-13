// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import AttributedCore
import Foundation
internal import AttributedEngineObjC
internal import AttributedViewObjC

#if canImport(UIKit)
import UIKit

public typealias PlatformView = UIView
#elseif canImport(AppKit)
import AppKit

public typealias PlatformView = NSView
#endif

public extension Attributed {
@MainActor
protocol TextViewDelegate: AnyObject {
    // Called for every recognized interaction, after any `.action` closure.
    func textView(_ textView: TextView, didRecognize event: InteractionEvent)
    // Whether an interaction whose value is a URL, such as `.link(_:)`, opens
    // it with the system. Defaults to true.
    func textView(_ textView: TextView, shouldOpen url: URL, event: InteractionEvent) -> Bool
}
}

public extension Attributed.TextViewDelegate {
    func textView(_ textView: Attributed.TextView, didRecognize event: Attributed.InteractionEvent) {}

    func textView(
        _ textView: Attributed.TextView,
        shouldOpen url: URL,
        event: Attributed.InteractionEvent
    ) -> Bool {
        true
    }
}

public extension Attributed {
// Display-only text view. Layout, drawing, tiling, and gesture recognition
// happen in the engine's display view; this wrapper owns the Swift-only
// parts: interaction handlers and AsyncImage loading.
@MainActor
final class TextView: PlatformView {
    let display = ATRTextDisplayView(frame: .zero)
    private var lowered: IR.LoweredText?
    // Identifies the current text so deferred image loads for replaced text
    // are dropped.
    private var textGeneration = 0
    private var isSettingPreparedText = false

    public var text: AttributedText? {
        didSet {
            if !isSettingPreparedText {
                display(text?.lower(), layout: nil)
            }
        }
    }

    // Zero means unlimited.
    public var maximumNumberOfLines = 0 {
        didSet { display.maximumNumberOfLines = UInt(max(0, maximumNumberOfLines)) }
    }

    public var truncationToken = "\u{2026}" {
        didSet { display.truncationToken = truncationToken }
    }

    public var lineHeightMode = LineHeightMode.typographic {
        didSet { display.lineHeightMode = ATRLineHeightMode(rawValue: lineHeightMode.rawValue)! }
    }

    // Off by default. When on, drawing is split into tiles and only tiles
    // near the visible part of the first enclosing scroll view are drawn.
    public var isViewportRenderingEnabled = false {
        didSet { display.isViewportRenderingEnabled = isViewportRenderingEnabled }
    }

    public var tileHeight: CGFloat = 256 {
        didSet { display.tileHeight = tileHeight }
    }

    // Off by default: emoji keep their own colors inside gradient text.
    public var appliesGradientToEmoji = false {
        didSet { display.appliesGradientToColorGlyphs = appliesGradientToEmoji }
    }

    // Off by default. When on, bitmaps, including decoding their images,
    // are drawn on a background queue and appear when finished. Fast
    // scrolling can then briefly show blank areas: a tile scrolled into view
    // stays empty until its bitmap is ready. Keep it off unless main-thread
    // drawing is the bottleneck.
    public var rendersAsynchronously = false {
        didSet { display.rendersAsynchronously = rendersAsynchronously }
    }

    public weak var delegate: TextViewDelegate?

    // The layout for the current width, or nil before the first layout pass.
    public var textLayout: TextLayout? {
        display.textLayout.map(TextLayout.init(engine:))
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    public convenience init(_ text: AttributedText) {
        self.init(frame: .zero)
        self.text = text
        display(text.lower(), layout: nil)
    }

    // Shows text prepared ahead of time. Its layout is used while it matches
    // this view's width, maximum number of lines, truncation token, and line
    // height mode; otherwise the view lays out again.
    public func setText(_ prepared: PreparedText) {
        isSettingPreparedText = true
        text = prepared.text
        isSettingPreparedText = false
        display(prepared.lowered, layout: prepared.layout)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    // The rounded-up size of the text laid out at `width`.
    public func measuredSize(forWidth width: CGFloat) -> CGSize {
        display.sizeThatFitsWidth(width)
    }

    public override var intrinsicContentSize: CGSize {
        display.intrinsicContentSize
    }

    #if canImport(UIKit)
    public override func sizeThatFits(_ size: CGSize) -> CGSize {
        measuredSize(forWidth: size.width)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        display.frame = bounds
    }
    #elseif canImport(AppKit)
    public override var isFlipped: Bool {
        true
    }

    public override func layout() {
        super.layout()
        display.frame = bounds
    }
    #endif

    private func configure() {
        addSubview(display)
        display.interactionHandler = { [weak self] interaction, location in
            MainActor.assumeIsolated {
                self?.perform(InteractionID(rawValue: interaction), at: location)
            }
        }
        display.contentSizeDidChangeHandler = { [weak self] in
            MainActor.assumeIsolated {
                self?.invalidateIntrinsicContentSize()
            }
        }

        #if canImport(UIKit)
        isAccessibilityElement = true
        accessibilityTraits = .staticText
        #elseif canImport(AppKit)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        #endif
    }

    private func display(_ lowered: IR.LoweredText?, layout: TextLayout?) {
        self.lowered = lowered
        textGeneration += 1
        display.setDocument(lowered?.document.engine, layout: layout?.engine)

        #if canImport(UIKit)
        accessibilityLabel = lowered?.document.engine.plainText
        #elseif canImport(AppKit)
        setAccessibilityLabel(lowered?.document.engine.plainText)
        #endif

        guard let lowered else {
            return
        }

        var deferred: [(AttachmentID, @MainActor () -> PlatformImage)] = []

        for index in lowered.imageSources.indices {
            let id = AttachmentID(rawValue: UInt32(index))

            switch lowered.imageSource(for: id) {
            case let .resolved(image):
                display.setImage(image, forAttachment: id.rawValue)
            case let .defer(load):
                deferred.append((id, load))
            }
        }

        guard !deferred.isEmpty else {
            return
        }

        // AsyncImage pipeline: load after the initial render, then let the
        // display view redraw or relayout.
        let generation = textGeneration
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.textGeneration == generation else {
                    return
                }

                for (id, load) in deferred {
                    self.display.setImage(load(), forAttachment: id.rawValue)
                }
            }
        }
    }

    private func perform(_ id: InteractionID, at location: CGPoint) {
        guard let lowered, Int(id.rawValue) < lowered.interactions.count else {
            return
        }

        let document = lowered.document.engine
        let range = document.range(forInteraction: id.rawValue)
        let rects = (display.textLayout?.rects(forInteraction: id.rawValue) ?? []).map { value in
            var rect = CGRect.zero
            value.getValue(&rect, size: MemoryLayout<CGRect>.size)
            return rect
        }
        let interaction = lowered.interaction(for: id)
        let value: Any?

        switch interaction {
        case .action:
            value = nil
        case let .value(attached):
            value = attached
        }

        let event = InteractionEvent(
            gesture: lowered.gesture(for: id),
            value: value,
            range: range,
            text: document.text(in: range),
            location: convert(location, from: display),
            rects: rects.map { convert($0, from: display) }
        )

        if case let .action(action) = interaction {
            action()
        }

        delegate?.textView(self, didRecognize: event)

        if let url = value as? URL, delegate?.textView(self, shouldOpen: url, event: event) ?? true {
            #if canImport(UIKit)
            UIApplication.shared.open(url)
            #elseif canImport(AppKit)
            NSWorkspace.shared.open(url)
            #endif
        }
    }
}
}

public extension Attributed {
@MainActor
struct InteractionEvent {
    public let gesture: Gesture
    // The value attached to the interaction, such as the URL of a link, or
    // nil for closure interactions.
    public let value: Any?
    // The interactive node's span in the document text, in UTF-16 units.
    // Paragraphs are joined by one newline and each attachment is one
    // U+FFFC, as in an NSAttributedString of the same text.
    public let range: NSRange
    public let text: String
    // Where the gesture was recognized, in the text view's coordinates.
    public let location: CGPoint
    // Every rect where the interaction can be hit, in the text view's
    // coordinates.
    public let rects: [CGRect]

    public func value<Value>(as type: Value.Type = Value.self) -> Value? {
        value as? Value
    }
}
}
