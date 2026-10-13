# Documentation

Attributed is being rewritten from scratch: a pure-Swift DSL on top, and an ObjC/C++ engine below that lays out and draws text with CoreText, exposed through a custom display-only text view. [`Package.swift`](../Package.swift) is the source of truth for products and deployment targets.

These documents double as the project's working memory. Update them in the same change as any decision or implementation they describe.

## Documentation map

| Document | Contents |
| --- | --- |
| [Goals and constraints](design/goals-and-constraints.md) | Scope, hard constraints, naming, code and Git conventions |
| [Architecture](design/architecture.md) | Layers, SwiftPM targets, language boundary, verification commands |
| [IR](design/ir.md) | Op stream, styles, resources, invariants, dump format |
| [DSL](design/dsl.md) | Nodes and modifiers: text, interactions, images, gradients |
| [Layout and rendering](design/layout-and-rendering.md) | Width-based immutable layout, off-main computation, drawing, viewport tiling, gradients across tiles |
| [Text geometry](design/text-geometry.md) | Public position and rect queries on a layout; the base for text selection |
| [Roadmap](design/roadmap.md) | Phases and progress checklist |
| [Decisions](design/decisions.md) | Decision log and open questions |

## Accuracy policy

The source and tests define current behavior. Each document marks what is implemented and what is planned. Private notes under `tmp/` are excluded from Git.

## Legacy documents

`api/`, `guides/`, and `specifications/` describe the deleted v0.1 implementation (`NSAttributedString` + TextKit 2) and are obsolete. They are kept until the user decides to remove them; the old code is recoverable from commit `def47d1`.
