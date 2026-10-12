// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

public extension Attributed {
// Combines nodes without adding anything of its own, like SwiftUI's Group.
// Inside a paragraph it groups inline nodes; at the top level it groups
// blocks. Modifiers applied to it, such as `onTap`, cover every child as one
// unit: one interaction, one range, merged hit regions.
struct Group<Element>: AttributedNode {
    let children: [any AttributedNode]

    public func lower(into builder: inout IR.Builder) {
        for child in children {
            child.lower(into: &builder)
        }
    }
}
}

extension Attributed.Group: Attributed.AttributedInline where Element == any Attributed.AttributedInline {
    public init(@Attributed.AttributedInlineBuilder content: () -> [any Attributed.AttributedInline]) {
        children = content().map { $0 as any Attributed.AttributedNode }
    }
}

extension Attributed.Group: Attributed.AttributedBlock where Element == any Attributed.AttributedBlock {
    public init(@Attributed.AttributedTextBuilder content: () -> [any Attributed.AttributedBlock]) {
        children = content().map { $0 as any Attributed.AttributedNode }
    }
}
