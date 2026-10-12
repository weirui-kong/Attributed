// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import Foundation

public extension Attributed {
// Identifiers are indices into the lowered text that created them.
struct InteractionID: Hashable, Sendable {
    public let rawValue: UInt32

    package init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
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
