# Core DSL

## Document grammar

`AAttributedText` contains block nodes. `AParagraph` is currently the built-in block node, and its builder accepts inline nodes including raw `String`, `AText`, `ALink`, and `AImage`.

Both result builders support conditionals and loops. Raw strings are accepted only by the inline builder and are converted to text nodes. The builder implementation is in [`Sources/Core/AttributedText.swift`](../../Sources/Core/AttributedText.swift).

```swift
let document = AAttributedText {
    AParagraph {
        "Tags: "

        for tag in tags {
            AText("[\(tag)] ")
                .foregroundColor(.systemOrange)
        }

        if isActive {
            AText("ACTIVE")
                .font(.boldSystemFont(ofSize: 12))
        }
    }
}
```

## Attribute inheritance

Rendering begins with a root text context whose foreground color is the platform semantic label color: `UIColor.label` on UIKit and `NSColor.labelColor` on AppKit. Unstyled text therefore follows light and dark appearance.

A paragraph merges its text and paragraph attributes into the parent context. Each inline node then merges only the values explicitly set on that node. An inline value overrides its paragraph value; an unset inline value inherits it. See [`Sources/Core/Attributes.swift`](../../Sources/Core/Attributes.swift).

Available text modifiers are:

- `font(_:)`
- `foregroundColor(_:)`
- `backgroundColor(_:)` on text and paragraph nodes
- `kern(_:)`
- `baselineOffset(_:)` on text nodes
- `underline(_:color:)` on text and link nodes

Available paragraph modifiers are:

- `alignment(_:)`
- `baseWritingDirection(_:)`
- `lineSpacing(_:)`
- `paragraphSpacing(_:)`

## Rendering result

`render()` returns `ARenderedAttributedText`. Its public `attributedString` is ready for TextKit or other APIs that accept `NSAttributedString`. Runtime attachment state, interactions, update streams, and cancellation remain owned by the rendered object, so keep that object alive while displaying asynchronous images.

The renderer appends a newline while constructing each paragraph so paragraph styles cover the terminator. It removes only the final document terminator before returning the result. Paragraph boundaries inside the document remain intact. The behavior is implemented in [`Sources/Core/Paragraph.swift`](../../Sources/Core/Paragraph.swift) and [`Sources/Core/AttributedText.swift`](../../Sources/Core/AttributedText.swift).
