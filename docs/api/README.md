# API Notes

These notes explain semantics that are not obvious from a declaration alone.

- [Core DSL](core-dsl.md): document structure, builders, inheritance, and modifiers.
- [Display APIs](display.md): TextKit 2 hosts, SwiftUI bridging, sizing, and appearance changes.
- [Image attachments](image-attachments.md): sources, sizing, alignment, loading state, and updates.
- [Remote images](remote-images.md): provider requirements, synchronous cache lookup, and `ImageDownloader`.
- [Links and interactions](interactions.md): URL attributes, custom action registration, and current host limitations.

Most application code should import `Attributed` and use the `A`-prefixed facade from [`Sources/Attributed/Aliases.swift`](../../Sources/Attributed/Aliases.swift). Import a lower-level product only when the application deliberately wants that narrower dependency.
