// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import CoreGraphics

public extension Attributed {
// Reserves horizontal room in a line and draws nothing. Without a height it
// is as tall as the adjacent text (the text before it, else after it, else
// its own font), so it never makes the line taller. In text ranges it counts
// as one U+FFFC, like an image.
struct Spacer: AttributedInline {
    let width: CGFloat
    let height: CGFloat?

    public init(width: CGFloat, height: CGFloat? = nil) {
        precondition(width.isFinite && width >= 0, "A spacer needs a finite, non-negative width.")
        precondition(height.map { $0.isFinite && $0 >= 0 } ?? true, "A spacer height must be finite and non-negative.")
        self.width = width
        self.height = height
    }

    public func lower(into builder: inout IR.Builder) {
        builder.spacer(width: width, height: height)
    }
}
}
