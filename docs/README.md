# Documentation

Attributed is a TextKit-first DSL for constructing and displaying `NSAttributedString` on iOS and macOS. The package currently requires Swift 5.9, iOS 16, and macOS 13; [`Package.swift`](../Package.swift) is the source of truth for deployment targets and products.

The public facade is the `Attributed` product. It re-exports the lower-level modules and provides `A`-prefixed aliases such as `AAttributedText`, `AText`, `AParagraph`, `AImage`, `ATextKitView`, and `ATextView`. See [`Sources/Attributed/Aliases.swift`](../Sources/Attributed/Aliases.swift) for the complete alias list.

## Documentation map

- [`guides/`](guides/README.md): installation, first use, and task-oriented examples.
- [`api/`](api/README.md): public API semantics and boundaries.
- [`specifications/`](specifications/README.md): architecture, loading behavior, and acceptance rules.
- [Project README](../README.md): short package overview and installation snippet.

## Package map

| Product | Responsibility | Implementation |
| --- | --- | --- |
| `Attributed` | Primary facade and `A`-prefixed aliases | [`Sources/Attributed/`](../Sources/Attributed/) |
| `AttributedCore` | DSL, rendering, interactions, attachments, and remote-provider contract | [`Sources/Core/`](../Sources/Core/) |
| `AttributedTextKit` | TextKit 2 hosts for UIKit and AppKit | [`Sources/TextKit/`](../Sources/TextKit/) |
| `AttributedSwiftUI` | SwiftUI bridge around the TextKit host | [`Sources/SwiftUI/`](../Sources/SwiftUI/) |
| `AttributedUtility` | Optional URLSession image downloader | [`Sources/Utility/`](../Sources/Utility/) |

## Accuracy policy

The source and tests define current behavior. Documents should distinguish implemented behavior from future work and link to the relevant relative path when a detail is not obvious. Private design notes under `tmp/` are intentionally excluded from the public documentation and from Git.
