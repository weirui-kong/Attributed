// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import Foundation

public extension Attributed {
struct Text: AttributedInline, InlineStyled {
    let content: String
    var inlineStyle = InlineStyle()
    var url: URL?

    public init(_ content: String) {
        self.content = content
    }

    public func lower(into builder: inout IR.Builder) {
        let style = inlineStyle.lowered(into: &builder)

        guard style != IR.TextStyle() || url != nil else {
            builder.text(content)
            return
        }

        let span = IR.Span(
            textStyle: style,
            interaction: url.map { builder.register(.value($0), gesture: .tap()) }
        )

        builder.span(span) { builder in
            builder.text(content)
        }
    }
}
}

public extension Attributed.Text {
    func font(_ value: PlatformFont) -> Self {
        withStyle { $0.font = value }
    }

    // The foreground is either a color or a gradient; the last one set wins.
    func foregroundColor(_ value: PlatformColor) -> Self {
        withStyle { $0.foreground = .color(value) }
    }

    func gradient(_ value: Attributed.TextGradient) -> Self {
        withStyle { $0.foreground = .gradient(value) }
    }

    func backgroundColor(_ value: PlatformColor) -> Self {
        withStyle { $0.backgroundColor = value }
    }

    func kern(_ value: CGFloat) -> Self {
        withStyle { $0.kern = value }
    }

    func baselineOffset(_ value: CGFloat) -> Self {
        withStyle { $0.baselineOffset = value }
    }

    // Without a color or gradient, the underline uses the text's foreground,
    // including a foreground gradient.
    func underline(
        _ style: Attributed.UnderlineStyle = .single,
        color: PlatformColor? = nil
    ) -> Self {
        withStyle {
            $0.underline = style
            $0.underlineFill = color.map { .color($0) }
        }
    }

    func underline(
        _ style: Attributed.UnderlineStyle = .single,
        gradient: Attributed.TextGradient
    ) -> Self {
        withStyle {
            $0.underline = style
            $0.underlineFill = .gradient(gradient)
        }
    }

    // A single tap carrying `url` as its value, like `onTap(value: url)`.
    // Link appearance is not implied; style the text explicitly.
    func link(_ url: URL) -> Self {
        var copy = self
        copy.url = url
        return copy
    }
}
