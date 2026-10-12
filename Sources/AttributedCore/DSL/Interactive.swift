// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import Foundation

public extension Attributed {
struct Interactive<Content: AttributedNode>: AttributedNode {
    let content: Content
    let gesture: Gesture
    let interaction: Interaction

    public func lower(into builder: inout IR.Builder) {
        let span = IR.Span(interaction: builder.register(interaction, gesture: gesture))

        builder.span(span) { builder in
            content.lower(into: &builder)
        }
    }
}
}

extension Attributed.Interactive: Attributed.AttributedInline
where Content: Attributed.AttributedInline {}

extension Attributed.Interactive: Attributed.AttributedBlock
where Content: Attributed.AttributedBlock {}

// The hosting text view recognizes the gesture, runs the action if any, and
// reports an InteractionEvent to its delegate.
public extension Attributed.AttributedNode {
    func onTap(
        count: Int = 1,
        _ action: @escaping @MainActor () -> Void
    ) -> Attributed.Interactive<Self> {
        precondition(count >= 1, "A tap needs at least one touch.")
        return Attributed.Interactive(content: self, gesture: .tap(count: count), interaction: .action(action))
    }

    // Reports `value` through the text view delegate when recognized.
    // Disfavored so that a trailing closure always selects the action
    // overload instead of becoming the value.
    @_disfavoredOverload
    func onTap<Value>(count: Int = 1, value: Value) -> Attributed.Interactive<Self> {
        precondition(count >= 1, "A tap needs at least one touch.")
        return Attributed.Interactive(content: self, gesture: .tap(count: count), interaction: .value(value))
    }

    func onLongPress(
        minimumDuration: TimeInterval = 0.5,
        _ action: @escaping @MainActor () -> Void
    ) -> Attributed.Interactive<Self> {
        precondition(minimumDuration.isFinite && minimumDuration >= 0)
        return Attributed.Interactive(
            content: self,
            gesture: .longPress(minimumDuration: minimumDuration),
            interaction: .action(action)
        )
    }

    // Reports `value` through the text view delegate when recognized.
    @_disfavoredOverload
    func onLongPress<Value>(
        minimumDuration: TimeInterval = 0.5,
        value: Value
    ) -> Attributed.Interactive<Self> {
        precondition(minimumDuration.isFinite && minimumDuration >= 0)
        return Attributed.Interactive(
            content: self,
            gesture: .longPress(minimumDuration: minimumDuration),
            interaction: .value(value)
        )
    }
}
