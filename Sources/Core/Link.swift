// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public extension Attributed {
struct Link: AttributedInline {
    let text: String
    let interaction: Interaction
    var attributes = TextAttributes()

    public init(_ text: String, url: URL) {
        self.text = text
        interaction = .url(url)
    }

    public init(_ text: String, action: @escaping () -> Void) {
        self.text = text
        interaction = .action(action)
    }

    public func render(context: RenderContext) -> NodeRenderResult {
        let id = context.interactions.register(interaction)
        let attributes = context.textAttributes.merging(attributes)
        let result = NSMutableAttributedString(
            string: text,
            attributes: attributes.nsAttributes
        )
        let range = NSRange(location: 0, length: result.length)

        result.addAttribute(.attributedInteractionID, value: id, range: range)

        if case let .url(url) = interaction {
            result.addAttribute(.link, value: url, range: range)
        }

        return NodeRenderResult(attributedString: result)
    }
}
}

public extension Attributed.Link {
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
