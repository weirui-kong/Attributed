# Display APIs

## UIKit and AppKit

`ATextKitView` is the facade alias for the platform-specific `TextKitView`.

```swift
let rendered = document.render()
let textView = ATextKitView()
textView.display(rendered)
```

On UIKit, the host is a `UIView` containing a non-editable, non-scrolling `UITextView` created with `UITextView(usingTextLayoutManager: true)`. On AppKit, the host is an `NSTextView` built from `NSTextContentStorage`, `NSTextLayoutManager`, and `NSTextContainer`. Both paths use TextKit 2 exclusively. See [`Sources/TextKit/TextKitView.swift`](../../Sources/TextKit/TextKitView.swift).

`heightThatFits(width:)` lays out the TextKit document at the supplied width and returns the layout manager's used height. Width must be greater than zero.

The hosts redraw when the platform appearance changes. Default DSL text carries a semantic label color in the attributed string itself; setting only a text view's `textColor` is not relied upon for light/dark adaptation.

## SwiftUI

`ATextView` accepts either a document or an already rendered value:

```swift
ATextView(document)

ATextView(rendered: rendered)
```

The bridge is a `UIViewRepresentable` or `NSViewRepresentable` around the same TextKit host. It implements SwiftUI's proposal-based `sizeThatFits` and uses the proposed width to measure text. It does not convert the content to SwiftUI `Text` or Foundation `AttributedString`. See [`Sources/SwiftUI/AttributedTextView.swift`](../../Sources/SwiftUI/AttributedTextView.swift).

## Attachment updates

The host observes `ARenderedAttributedText.updates()`:

- Content-only attachment changes invalidate rendering.
- Size changes invalidate layout and intrinsic content size.
- State-only changes do not trigger an additional layout operation.

Placeholder and final image content use the same `NSTextAttachment`. The host only invalidates TextKit rendering or layout when that attachment changes. The update model is defined in [`Sources/Core/AttachmentRuntime.swift`](../../Sources/Core/AttachmentRuntime.swift).
