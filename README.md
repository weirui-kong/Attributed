# Attributed

> [!WARNING]
> 🚧 **Under Development** — The current API is an early v0.1 design and may change before the first stable release.

Attributed is a Swift DSL for building `NSAttributedString` with composable paragraphs, inline styles, links, and explicit attribute inheritance. It supports iOS and macOS and keeps optional integrations separate from the rendering core.

## Requirements

- Swift 5.9 or later
- iOS 15 or later
- macOS 12 or later

## Installation

Add the package in Xcode using:

```text
https://github.com/weirui-kong/Attributed.git
```

Or add it to `Package.swift`:

```swift
dependencies: [
    .package(
        url: "https://github.com/weirui-kong/Attributed.git",
        branch: "main"
    )
]
```

Then add the `Attributed` product to your target:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "Attributed", package: "Attributed")
    ]
)
```

## Usage

```swift
import Attributed
import Foundation

let document = AAttributedText {
    AParagraph {
        "Hello "

        AText("Attributed")
            .font(.boldSystemFont(ofSize: 20))
            .foregroundColor(.systemBlue)
            .underline()

        "! Visit "

        ALink(
            "the project",
            url: URL(string: "https://github.com/weirui-kong/Attributed")!
        )
        .foregroundColor(.systemBlue)
        .underline()
    }
    .font(.systemFont(ofSize: 16))
    .lineSpacing(4)
    .paragraphSpacing(8)
}

let rendered = document.render()
let attributedString = rendered.attributedString
```

Paragraph attributes are inherited by inline nodes. An inline node overrides only the attributes explicitly applied to it.

Result builders support raw strings, conditionals, and loops:

```swift
AAttributedText {
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

## SwiftUI

Standard attributed-string content can be displayed in SwiftUI by converting the rendered result:

```swift
import Attributed
import SwiftUI

let rendered = document.render()

Text(AttributedString(rendered.attributedString))
```

The `A`-prefixed facade avoids collisions with `SwiftUI.Text`, `SwiftUI.Link`, and `SwiftUI.Image`.

Custom interactions, TextKit-specific layout invalidation, and asynchronous attachments will use dedicated host adapters as those features are implemented.

## Modules

| Module | Purpose |
| --- | --- |
| `Attributed` | Primary facade containing the `A`-prefixed public aliases. |
| `AttributedCore` | DSL nodes, attribute inheritance, rendering, and interaction state. |
| `AttributedUtility` | Optional and replaceable integrations such as remote image loading. |

Most applications should depend only on `Attributed`.

## Current Features

- Paragraph and inline node grammar
- Immutable text and paragraph modifiers
- Font, foreground and background color, kern, baseline offset, and underline attributes
- Alignment, writing direction, line spacing, and paragraph spacing
- Raw strings, conditionals, and loops in result builders
- URL links and custom interaction registration
- iOS and macOS support

## Planned

- Synchronous image attachments
- Fixed, intrinsic, and adaptive attachment sizing
- Asynchronous images with placeholders and update observation
- UIKit and AppKit host adapters
- Optional remote image loading in `AttributedUtility`

## Demo

The example app is located in [`Demo/AttributedDemo`](Demo/AttributedDemo). It includes visual test pages for long text, mixed inline styles, paragraph layout, links, and left-to-right and right-to-left content.

## Documentation

Design specifications, API notes, and guides live in [`docs`](docs).

## License

Attributed is available under the MIT License. See [`LICENSE`](LICENSE) for details.
