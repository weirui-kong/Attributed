// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import CoreGraphics

public extension Attributed {
struct Paragraph: AttributedBlock, InlineStyled {
    let children: [any AttributedInline]
    var inlineStyle = InlineStyle()
    var paragraphStyle = IR.ParagraphStyle()

    public init(
        @AttributedInlineBuilder content: () -> [any AttributedInline]
    ) {
        children = content()
    }

    public func lower(into builder: inout IR.Builder) {
        let textStyle = inlineStyle.lowered(into: &builder)

        builder.paragraph(paragraphStyle, textStyle: textStyle) { builder in
            for child in children {
                child.lower(into: &builder)
            }
        }
    }
}
}

public extension Attributed.Paragraph {
    func font(_ value: PlatformFont) -> Self {
        withStyle { $0.font = value }
    }

    func foregroundColor(_ value: PlatformColor) -> Self {
        withStyle { $0.foreground = .color(value) }
    }

    func backgroundColor(_ value: PlatformColor) -> Self {
        withStyle { $0.backgroundColor = value }
    }

    func kern(_ value: CGFloat) -> Self {
        withStyle { $0.kern = value }
    }

    func alignment(_ value: Attributed.TextAlignment) -> Self {
        withParagraphStyle { $0.alignment = value }
    }

    func baseWritingDirection(_ value: Attributed.WritingDirection) -> Self {
        withParagraphStyle { $0.writingDirection = value }
    }

    func lineSpacing(_ value: CGFloat) -> Self {
        withParagraphStyle { $0.lineSpacing = Double(value) }
    }

    func paragraphSpacing(_ value: CGFloat) -> Self {
        withParagraphStyle { $0.paragraphSpacing = Double(value) }
    }

    private func withParagraphStyle(
        _ update: (inout Attributed.IR.ParagraphStyle) -> Void
    ) -> Self {
        var copy = self
        update(&copy.paragraphStyle)
        return copy
    }
}
