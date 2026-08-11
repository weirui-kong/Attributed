// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import Foundation

public extension Attributed {
enum AttachmentState {
    case loading
    case resolved
    case failed(any Error)
    case cancelled
}

enum RenderedTextUpdate {
    case attachmentContentChanged(id: AttachmentID, range: NSRange)
    case attachmentLayoutChanged(id: AttachmentID, range: NSRange)
    case attachmentStateChanged(id: AttachmentID, range: NSRange)
}

final class RenderedAttachment {
    public let id: AttachmentID
    public let range: NSRange
    public private(set) var state: AttachmentState
    public var accessibilityLabel: String? {
        attachment.imageAccessibilityLabel
    }

    let attachment: ImageTextAttachment

    init(
        id: AttachmentID,
        range: NSRange,
        state: AttachmentState,
        attachment: ImageTextAttachment
    ) {
        self.id = id
        self.range = range
        self.state = state
        self.attachment = attachment
    }

    func setState(_ state: AttachmentState) {
        self.state = state
    }
}
}
