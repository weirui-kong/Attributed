# Goals and Constraints

## Goals

- Build a text layout and drawing engine directly on CoreText, and ship a high-performance display component comparable to `UITextView`.
- Display only. No editing, input methods, or rich selection. Simple tap interactions (links and `onTap`) are in scope.

## Hard constraints

- Never export `NSAttributedString`, never use TextKit, and keep no TextKit reference backend.
  - CoreText's `CTTypesetter` and `CTLine` only accept `CFAttributedString`. The engine may build one per paragraph internally and discard it; it is never the document model and never leaves the engine.
- The public API is pure Swift: the DSL plus Swift wrappers. Callers never see `@objc` or Objective-C types.
- Swift is only a thin top-level wrapper. All heavy computation is written in Objective-C/C++: document storage, resource deduplication, style resolution, run tables, layout, drawing, and hit testing. Anything that talks to CoreText is never written in Swift.
- Platforms: iOS 16+ and macOS 13+. The engine is platform-neutral; views are iOS-first.

## Naming

- Every Objective-C/ObjC++ symbol uses the `ATR` prefix, for example `ATRTextView`.
- Public Swift facade aliases also use `ATR`: `ATRText`, `ATRParagraph`, `ATRImage`, and so on. The former `A` prefix is retired.
- Concrete Swift types live under the `Attributed` namespace in the `AttributedCore` module.

## Code conventions

From [`AGENTS.md`](../../AGENTS.md):

- Every Swift file starts with the MIT license header. In `Package.swift`, the `// swift-tools-version:` line comes first and the header follows it.
- Never use `///` documentation comments; use `//` only. Comment only behavior, intent, constraints, or non-obvious decisions.
- Objective-C headers never use `NS_ASSUME_NONNULL_BEGIN` / `NS_ASSUME_NONNULL_END`; every pointer, including `instancetype` returns, is explicitly annotated `nonnull` / `nullable` (`_Nonnull` / `_Nullable` for C pointers).

## Git conventions

- Commit messages start with a `type: summary` line matching the existing history, optionally followed by a blank line and a short body. Never add `Co-Authored-By` or any other AI attribution.
- Commit or push only when asked.
