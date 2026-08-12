# Architecture Specification

## Goals

- Keep document construction independent from SwiftUI.
- Use `NSAttributedString` as the rendered representation.
- Use TextKit 2 as the only built-in display engine.
- Support image-backed attachments only; do not introduce arbitrary view attachments.
- Keep optional remote downloading outside Core.
- Expose a facade that avoids collisions with SwiftUI names.

## Module boundaries

`AttributedCore` owns the DSL, platform type aliases, rendering context, interaction registry, attachment runtime, and `RemoteImageProvider` protocol. It does not depend on `AttributedUtility`, `AttributedTextKit`, or `AttributedSwiftUI`.

`AttributedTextKit` depends only on Core and owns UIKit/AppKit hosts. `AttributedSwiftUI` depends on Core and TextKit and only bridges the host. `AttributedUtility` depends on Core and provides an optional provider implementation. `Attributed` re-exports Core, TextKit, and SwiftUI and declares the `A`-prefixed aliases.

The dependency graph is declared in [`Package.swift`](../../Package.swift).

## Rendering pipeline

1. `AAttributedText` stores block nodes created by its result builder.
2. `render()` creates the root text and paragraph context plus an interaction registry.
3. Each paragraph merges inherited attributes and renders its inline children.
4. The renderer returns `ARenderedAttributedText` containing the `NSAttributedString`, registered interactions, discovered attachments, loading tasks, and update continuations.
5. A TextKit host displays that rendered object and observes its update stream.
6. The SwiftUI view delegates display and measurement to the same TextKit host.

## Ownership rules

- DSL nodes are value types and modifiers return modified copies.
- `ARenderedAttributedText` is a reference type because attachment state changes after initial rendering.
- The caller should retain the rendered object while it is displayed.
- Deinitializing the rendered object cancels its tracked tasks and finishes update continuations.
- Remote-provider installation is process-wide through `ARemoteImageEnvironment.provider`.

## Public facade

The `A` prefix is the supported collision-avoidance mechanism for names such as `Text`, `Link`, and `Image`. It is implemented with type aliases rather than wrapper types, so facade and underlying values have identical behavior.

## Attachment scope

The attachment model is intentionally narrow:

- `AImage` is the only built-in attachment node.
- A source resolves to one `PlatformImage`.
- Async and remote loading may change the image and layout, but not the attachment content type.
- UIKit, AppKit, SwiftUI, and Core Animation view/layer embedding are not supported.
- `NSTextAttachmentViewProvider` must not be introduced by the built-in image path.

This constraint keeps Core independent from view lifecycle management and prevents TextKit viewport recycling from affecting attachment visibility.
