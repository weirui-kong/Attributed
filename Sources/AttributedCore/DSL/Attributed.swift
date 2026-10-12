// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

public enum Attributed {
public protocol AttributedNode {
    func lower(into builder: inout IR.Builder)
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

    public func lower() -> IR.LoweredText {
        var builder = IR.Builder()

        for child in children {
            child.lower(into: &builder)
        }

        return builder.finish()
    }
}
}
