// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import Foundation

public extension Attributed {
// Identifiers are indices into the lowered text that created them.
struct InteractionID: Hashable, Sendable {
    public let rawValue: UInt32
}

// What an interaction carries. Every recognized interaction reaches the text
// view's delegate as an InteractionEvent; `.action` also runs its closure.
enum Interaction {
    case action(@MainActor () -> Void)
    // Any value attached with `onTap(count:value:)`,
    // `onLongPress(minimumDuration:value:)`, or `.link(_:)`.
    case value(Any)
}

// Nested interactions keep only the innermost gesture of each kind; taps
// with different counts are different kinds, so a single tap and a double
// tap can share text, with the single tap waiting for the double tap to fail.
enum Gesture: Hashable, Sendable {
    case tap(count: Int = 1)
    case longPress(minimumDuration: TimeInterval = 0.5)
}
}

public extension Attributed {
@MainActor
struct InteractionEvent {
    public let gesture: Gesture
    // The value attached to the interaction, such as the URL of a link, or
    // nil for closure interactions.
    public let value: Any?
    // The interactive node's span in the document text, in UTF-16 units.
    // Paragraphs are joined by one newline and each attachment is one
    // U+FFFC, as in an NSAttributedString of the same text.
    public let range: NSRange
    public let text: String
    // Where the gesture was recognized, in the text view's coordinates.
    public let location: CGPoint
    // Every rect where the interaction can be hit, in the text view's
    // coordinates.
    public let rects: [CGRect]

    public func value<Value>(as type: Value.Type = Value.self) -> Value? {
        value as? Value
    }
}
}
