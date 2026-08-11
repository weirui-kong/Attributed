// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import Foundation

public enum Attributed {
public protocol AttributedNode {
    func render(context: RenderContext) -> NodeRenderResult
}

public protocol AttributedBlock: AttributedNode {}

public protocol AttributedInline: AttributedNode {}

@resultBuilder
public enum AttributedTextBuilder {
    public static func buildBlock(
        _ components: [any AttributedBlock]...
    ) -> [any AttributedBlock] {
        components.flatMap { $0 }
    }

    public static func buildExpression<N: AttributedBlock>(
        _ expression: N
    ) -> [any AttributedBlock] {
        [expression]
    }

    public static func buildOptional(
        _ component: [any AttributedBlock]?
    ) -> [any AttributedBlock] {
        component ?? []
    }

    public static func buildEither(
        first component: [any AttributedBlock]
    ) -> [any AttributedBlock] {
        component
    }

    public static func buildEither(
        second component: [any AttributedBlock]
    ) -> [any AttributedBlock] {
        component
    }

    public static func buildArray(
        _ components: [[any AttributedBlock]]
    ) -> [any AttributedBlock] {
        components.flatMap { $0 }
    }
}

@resultBuilder
public enum AttributedInlineBuilder {
    public static func buildBlock(
        _ components: [any AttributedInline]...
    ) -> [any AttributedInline] {
        components.flatMap { $0 }
    }

    public static func buildExpression<N: AttributedInline>(
        _ expression: N
    ) -> [any AttributedInline] {
        [expression]
    }

    public static func buildExpression(
        _ expression: String
    ) -> [any AttributedInline] {
        [Text(expression)]
    }

    public static func buildOptional(
        _ component: [any AttributedInline]?
    ) -> [any AttributedInline] {
        component ?? []
    }

    public static func buildEither(
        first component: [any AttributedInline]
    ) -> [any AttributedInline] {
        component
    }

    public static func buildEither(
        second component: [any AttributedInline]
    ) -> [any AttributedInline] {
        component
    }

    public static func buildArray(
        _ components: [[any AttributedInline]]
    ) -> [any AttributedInline] {
        components.flatMap { $0 }
    }
}

public struct AttributedText {
    let children: [any AttributedBlock]

    public init(
        @AttributedTextBuilder content: () -> [any AttributedBlock]
    ) {
        children = content()
    }

    public func render() -> RenderedAttributedText {
        let interactions = InteractionRegistry()
        let context = RenderContext(
            textAttributes: TextAttributes(),
            paragraphAttributes: ParagraphAttributes(),
            interactions: interactions
        )
        let result = NSMutableAttributedString()

        for child in children {
            result.append(child.render(context: context).attributedString)
        }

        if result.string.last == "\n" {
            result.deleteCharacters(in: NSRange(location: result.length - 1, length: 1))
        }

        return RenderedAttributedText(
            attributedString: result,
            interactions: interactions
        )
    }
}

public struct RenderContext {
    var textAttributes: TextAttributes
    var paragraphAttributes: ParagraphAttributes
    let interactions: InteractionRegistry

    init(
        textAttributes: TextAttributes,
        paragraphAttributes: ParagraphAttributes,
        interactions: InteractionRegistry
    ) {
        self.textAttributes = textAttributes
        self.paragraphAttributes = paragraphAttributes
        self.interactions = interactions
    }
}

public struct NodeRenderResult {
    public let attributedString: NSAttributedString

    public init(attributedString: NSAttributedString) {
        self.attributedString = attributedString
    }
}

public final class RenderedAttributedText {
    public let attributedString: NSAttributedString
    let interactions: InteractionRegistry

    init(
        attributedString: NSAttributedString,
        interactions: InteractionRegistry
    ) {
        self.attributedString = attributedString
        self.interactions = interactions
    }

    public func interaction(for id: InteractionID) -> Interaction? {
        interactions.interaction(for: id)
    }
}
}
