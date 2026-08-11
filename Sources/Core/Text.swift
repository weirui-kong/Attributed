// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public extension Attributed {
struct Text: AttributedInline {
    let content: String
    var attributes = TextAttributes()

    public init(_ content: String) {
        self.content = content
    }

    public func render(context: RenderContext) -> NodeRenderResult {
        let attributes = context.textAttributes.merging(attributes)
        let attributedString = NSAttributedString(
            string: content,
            attributes: attributes.nsAttributes
        )

        return NodeRenderResult(attributedString: attributedString)
    }
}
}

public extension Attributed.Text {
    func font(_ value: PlatformFont) -> Self {
        var copy = self
        copy.attributes.font = value
        return copy
    }

    func foregroundColor(_ value: PlatformColor) -> Self {
        var copy = self
        copy.attributes.foregroundColor = value
        return copy
    }

    func backgroundColor(_ value: PlatformColor) -> Self {
        var copy = self
        copy.attributes.backgroundColor = value
        return copy
    }

    func kern(_ value: CGFloat) -> Self {
        var copy = self
        copy.attributes.kern = value
        return copy
    }

    func baselineOffset(_ value: CGFloat) -> Self {
        var copy = self
        copy.attributes.baselineOffset = value
        return copy
    }

    func underline(
        _ style: NSUnderlineStyle = .single,
        color: PlatformColor? = nil
    ) -> Self {
        var copy = self
        copy.attributes.underlineStyle = style
        copy.attributes.underlineColor = color
        return copy
    }
}
