# Specifications

Specifications record behavior that must remain stable across implementations. They describe the current implementation, not an aspirational roadmap.

- [Architecture](architecture.md): package boundaries and rendering pipeline.
- [Attachment loading](attachment-loading.md): synchronous cache, asynchronous resolution, state, and invalidation rules.
- [TextKit rendering](textkit-rendering.md): host requirements, sizing, appearance, and image-backed attachments.

Executable coverage is located in [`Tests/CoreTests/`](../../Tests/CoreTests/), [`Tests/TextKitTests/`](../../Tests/TextKitTests/), and [`Tests/UtilityTests/`](../../Tests/UtilityTests/).
