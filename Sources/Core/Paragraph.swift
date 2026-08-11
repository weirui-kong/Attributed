// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public extension Attributed {
struct Paragraph: AttributedBlock {
    let children: [any AttributedInline]
    var textAttributes = TextAttributes()
    var paragraphAttributes = ParagraphAttributes()

    public init(
        @AttributedInlineBuilder content: () -> [any AttributedInline]
    ) {
        children = content()
    }

    public func render(context: RenderContext) -> NodeRenderResult {
        var childContext = context
        childContext.textAttributes = context.textAttributes.merging(textAttributes)
        childContext.paragraphAttributes = context.paragraphAttributes.merging(paragraphAttributes)

        let result = NSMutableAttributedString()

        for child in children {
            result.append(child.render(context: childContext).attributedString)
        }

        result.append(
            NSAttributedString(
                string: "\n",
                attributes: childContext.textAttributes.nsAttributes
            )
        )
        result.addAttribute(
            .paragraphStyle,
            value: childContext.paragraphAttributes.makeNSParagraphStyle(),
            range: NSRange(location: 0, length: result.length)
        )

        return NodeRenderResult(attributedString: result)
    }
}
}

public extension Attributed.Paragraph {
    func font(_ value: PlatformFont) -> Self {
        var copy = self
        copy.textAttributes.font = value
        return copy
    }

    func foregroundColor(_ value: PlatformColor) -> Self {
        var copy = self
        copy.textAttributes.foregroundColor = value
        return copy
    }

    func backgroundColor(_ value: PlatformColor) -> Self {
        var copy = self
        copy.textAttributes.backgroundColor = value
        return copy
    }

    func kern(_ value: CGFloat) -> Self {
        var copy = self
        copy.textAttributes.kern = value
        return copy
    }

    func alignment(_ value: NSTextAlignment) -> Self {
        var copy = self
        copy.paragraphAttributes.alignment = value
        return copy
    }

    func baseWritingDirection(_ value: NSWritingDirection) -> Self {
        var copy = self
        copy.paragraphAttributes.baseWritingDirection = value
        return copy
    }

    func lineSpacing(_ value: CGFloat) -> Self {
        var copy = self
        copy.paragraphAttributes.lineSpacing = value
        return copy
    }

    func paragraphSpacing(_ value: CGFloat) -> Self {
        var copy = self
        copy.paragraphAttributes.paragraphSpacing = value
        return copy
    }
}
