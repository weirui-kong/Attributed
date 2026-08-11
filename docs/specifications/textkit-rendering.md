# TextKit Rendering Specification

## Engine requirement

All built-in hosts must use TextKit 2. UIKit constructs `UITextView` with `usingTextLayoutManager: true`. AppKit explicitly connects `NSTextContentStorage`, `NSTextLayoutManager`, and `NSTextContainer`.

## Host behavior

- Displaying the same `ARenderedAttributedText` instance again is a no-op.
- Displaying a new instance cancels the previous observation task, replaces text content, invalidates intrinsic size, and starts observing the new update stream.
- UIKit's internal text view is non-editable and non-scrolling with zero text-container inset and line-fragment padding.
- AppKit's text view is non-editable, selectable, vertically resizable, and configured so its text container tracks width.
- Host backgrounds are transparent.

## Measurement

`heightThatFits(width:)` requires a positive width. The host assigns that width to the text container, ensures layout for the document range, and returns the ceiling of the layout manager's usage height with a minimum of one point.

The SwiftUI bridge returns no custom size when the proposal has no positive width. Otherwise it returns the proposed width and the TextKit-measured height.

## Appearance

Root DSL text must contain `UIColor.label` or `NSColor.labelColor` as its attributed foreground color. UIKit redraws when its trait collection reports a different color appearance. AppKit redraws when effective appearance changes.

Explicit fixed colors remain fixed. Callers that need adaptation should pass platform semantic or dynamic colors.

## Image attachment rendering

Placeholder and resolved image content must use the same `ImageTextAttachment`. An async or remote image without an explicit placeholder remains empty until resolution. The implementation must report `usesTextAttachmentView == false` and must not use `NSTextAttachmentViewProvider`, because attachment views can be recycled as TextKit layout fragments enter and leave the viewport.

TextKit hosts must respond to attachment update types as follows:

- Content change: invalidate rendering attributes and redraw.
- Layout change: invalidate layout, request layout and display, and invalidate intrinsic content size.
- State-only change: no additional TextKit invalidation.

The implementation is in [`Sources/TextKit/TextKitView.swift`](../../Sources/TextKit/TextKitView.swift) and [`Sources/Core/Image.swift`](../../Sources/Core/Image.swift).
