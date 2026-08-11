// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import AttributedCore

#if canImport(UIKit)
import UIKit

public final class TextKitView: UIView {
    public let textView: UITextView
    private var measuredWidth: CGFloat = 0
    private var renderedText: Attributed.RenderedAttributedText?
    private var updateTask: Task<Void, Never>?

    public var textLayoutManager: NSTextLayoutManager? {
        textView.textLayoutManager
    }

    public init() {
        textView = UITextView(usingTextLayoutManager: true)
        super.init(frame: .zero)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    public func display(_ rendered: Attributed.RenderedAttributedText) {
        guard renderedText !== rendered else {
            return
        }

        updateTask?.cancel()
        renderedText = rendered
        textView.attributedText = rendered.attributedString
        invalidateIntrinsicContentSize()
        observeUpdates(from: rendered)
    }

    public func heightThatFits(width: CGFloat) -> CGFloat {
        guard width > 0, let textLayoutManager else {
            return 1
        }

        textView.textContainer.size = CGSize(
            width: width,
            height: .greatestFiniteMagnitude
        )

        if let documentRange = textLayoutManager.textContentManager?.documentRange {
            textLayoutManager.ensureLayout(for: documentRange)
        }

        return max(1, ceil(textLayoutManager.usageBoundsForTextContainer.height))
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        textView.frame = bounds

        guard bounds.width != measuredWidth else {
            return
        }

        measuredWidth = bounds.width
        invalidateIntrinsicContentSize()
    }

    public override var intrinsicContentSize: CGSize {
        guard bounds.width > 0 else {
            return super.intrinsicContentSize
        }

        return textView.sizeThatFits(
            CGSize(width: bounds.width, height: .greatestFiniteMagnitude)
        )
    }

    public override func traitCollectionDidChange(
        _ previousTraitCollection: UITraitCollection?
    ) {
        super.traitCollectionDidChange(previousTraitCollection)

        guard traitCollection.hasDifferentColorAppearance(
            comparedTo: previousTraitCollection
        ) else {
            return
        }

        textView.setNeedsDisplay()
    }

    private func configure() {
        addSubview(textView)
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textColor = .label
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = true
    }

    private func observeUpdates(
        from rendered: Attributed.RenderedAttributedText
    ) {
        updateTask = Task { @MainActor [weak self, weak rendered] in
            guard let rendered else {
                return
            }

            for await update in rendered.updates() {
                self?.apply(update)
            }
        }
    }

    private func apply(_ update: Attributed.RenderedTextUpdate) {
        guard let textLayoutManager else {
            return
        }

        switch update {
        case let .attachmentContentChanged(_, range):
            if let textRange = textLayoutManager.textRange(for: range) {
                textLayoutManager.invalidateRenderingAttributes(for: textRange)
            }

            textView.setNeedsDisplay()
        case let .attachmentLayoutChanged(_, range):
            if let textRange = textLayoutManager.textRange(for: range) {
                textLayoutManager.invalidateLayout(for: textRange)
            }

            textView.setNeedsLayout()
            textView.setNeedsDisplay()
            invalidateIntrinsicContentSize()
        case .attachmentStateChanged:
            break
        }
    }
}
#elseif canImport(AppKit)
import AppKit

public final class TextKitView: NSTextView {
    private let contentStorage: NSTextContentStorage
    private var renderedText: Attributed.RenderedAttributedText?
    private var updateTask: Task<Void, Never>?

    public init() {
        let contentStorage = NSTextContentStorage()
        let layoutManager = NSTextLayoutManager()
        let textContainer = NSTextContainer()

        contentStorage.addTextLayoutManager(layoutManager)
        layoutManager.textContainer = textContainer
        self.contentStorage = contentStorage
        super.init(frame: .zero, textContainer: textContainer)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    public func display(_ rendered: Attributed.RenderedAttributedText) {
        guard renderedText !== rendered else {
            return
        }

        updateTask?.cancel()
        renderedText = rendered
        contentStorage.textStorage?.setAttributedString(rendered.attributedString)
        invalidateIntrinsicContentSize()
        observeUpdates(from: rendered)
    }

    public func heightThatFits(width: CGFloat) -> CGFloat {
        guard width > 0, let textLayoutManager else {
            return 1
        }

        textContainer?.size = CGSize(
            width: width,
            height: .greatestFiniteMagnitude
        )

        if let documentRange = textLayoutManager.textContentManager?.documentRange {
            textLayoutManager.ensureLayout(for: documentRange)
        }

        return max(1, ceil(textLayoutManager.usageBoundsForTextContainer.height))
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    private func configure() {
        isEditable = false
        isSelectable = true
        drawsBackground = false
        textColor = .labelColor
        textContainerInset = .zero
        textContainer?.lineFragmentPadding = 0
        isHorizontallyResizable = false
        isVerticallyResizable = true
        textContainer?.widthTracksTextView = true
    }

    private func observeUpdates(
        from rendered: Attributed.RenderedAttributedText
    ) {
        updateTask = Task { @MainActor [weak self, weak rendered] in
            guard let rendered else {
                return
            }

            for await update in rendered.updates() {
                self?.apply(update)
            }
        }
    }

    private func apply(_ update: Attributed.RenderedTextUpdate) {
        guard let textLayoutManager else {
            return
        }

        switch update {
        case let .attachmentContentChanged(_, range):
            if let textRange = textLayoutManager.textRange(for: range) {
                textLayoutManager.invalidateRenderingAttributes(for: textRange)
            }

            needsDisplay = true
        case let .attachmentLayoutChanged(_, range):
            if let textRange = textLayoutManager.textRange(for: range) {
                textLayoutManager.invalidateLayout(for: textRange)
            }

            needsLayout = true
            needsDisplay = true
            invalidateIntrinsicContentSize()
        case .attachmentStateChanged:
            break
        }
    }
}
#endif

private extension NSTextLayoutManager {
    func textRange(for range: NSRange) -> NSTextRange? {
        guard let contentManager = textContentManager else {
            return nil
        }

        let documentStart = contentManager.documentRange.location

        guard
            let start = contentManager.location(
                documentStart,
                offsetBy: range.location
            ),
            let end = contentManager.location(
                start,
                offsetBy: range.length
            )
        else {
            return nil
        }

        return NSTextRange(location: start, end: end)
    }
}
