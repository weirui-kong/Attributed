// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import Foundation

public extension Attributed {
// Identifiers are indices into the lowered text that created them.
struct AttachmentID: Hashable, Sendable {
    public let rawValue: UInt32
}

enum AttachmentSize: Hashable, Sendable {
    case fixed(width: CGFloat, height: CGFloat)
    // Preserves the aspect ratio, fits the maxima and the available line
    // width, and never upscales.
    case adaptive(maxWidth: CGFloat? = nil, maxHeight: CGFloat? = nil)
}

enum AttachmentAlignment: Hashable, Sendable {
    case baseline
    case center
    case top
    case bottom
    case offset(CGFloat)
}

enum ImageSource {
    // Image pipeline: the content is available when the text is lowered.
    case resolved(PlatformImage)
    // AsyncImage pipeline: the host calls the closure after the initial
    // render and updates the rendering once the image is installed.
    case `defer`(@MainActor () -> PlatformImage)
}

struct Image: AttributedInline {
    let source: ImageSource
    let sizePolicy: AttachmentSize
    let accessibilityLabel: String?
    var alignmentPolicy = AttachmentAlignment.baseline

    public init(
        _ source: ImageSource,
        size: AttachmentSize,
        accessibilityLabel: String? = nil
    ) {
        Self.validate(size)
        self.source = source
        sizePolicy = size
        self.accessibilityLabel = accessibilityLabel?.isEmpty == false
            ? accessibilityLabel
            : nil
    }

    public func alignment(_ value: AttachmentAlignment) -> Self {
        var copy = self
        copy.alignmentPolicy = value
        return copy
    }

    public func lower(into builder: inout IR.Builder) {
        builder.image(
            IR.AttachmentDescriptor(
                size: sizePolicy,
                alignment: alignmentPolicy,
                accessibilityLabel: accessibilityLabel
            ),
            source: source
        )
    }

    private static func validate(_ size: AttachmentSize) {
        switch size {
        case let .fixed(width, height):
            precondition(width.isFinite && width > 0)
            precondition(height.isFinite && height > 0)
        case let .adaptive(maxWidth, maxHeight):
            precondition(maxWidth != nil || maxHeight != nil)

            if let maxWidth {
                precondition(maxWidth.isFinite && maxWidth > 0)
            }

            if let maxHeight {
                precondition(maxHeight.isFinite && maxHeight > 0)
            }
        }
    }
}
}
