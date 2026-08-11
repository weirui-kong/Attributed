# Getting Started

## 1. Add the package

Add the repository as a Swift Package dependency and link the `Attributed` product to the application target. Current deployment requirements are iOS 16 or macOS 13.

## 2. Compose a document

```swift
import Attributed

let document = AAttributedText {
    AParagraph {
        "Hello "
        AText("Attributed")
            .font(.boldSystemFont(ofSize: 20))
            .foregroundColor(.systemBlue)
        "."
    }
    .font(.systemFont(ofSize: 17))
    .lineSpacing(4)
    .paragraphSpacing(8)
}
```

Plain strings inherit paragraph styling. Explicit text modifiers override only their corresponding inherited values. Unspecified foreground color uses the platform semantic label color.

## 3. Display in SwiftUI

```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        ATextView(document)
    }
}
```

If the same rendered object must be shared or observed, render it once:

```swift
let rendered = document.render()

ATextView(rendered: rendered)
```

Keep `rendered` alive for the lifetime of asynchronous attachments.

## 4. Display in UIKit or AppKit

```swift
let rendered = document.render()
let textView = ATextKitView()
textView.display(rendered)
```

The host reports content height through `heightThatFits(width:)`. Its parent remains responsible for supplying layout constraints or a frame.

## 5. Choose the appropriate import

Use `import Attributed` in ordinary application code. Import `AttributedCore`, `AttributedTextKit`, `AttributedSwiftUI`, or `AttributedUtility` directly only when the target intentionally depends on that individual product.
