# Roadmap

## P0: DSL and IR (pure Swift)

- [x] Delete the v0.1 sources, tests, and demo (recoverable from `def47d1`).
- [x] New package with tools 6.0 and the Swift 6 language mode; now three products (`Attributed`, `AttributedCore`, `AttributedUI`).
- [x] IR: op stream, styles, deduplicated resource tables, builder, dump.
- [x] Nodes `Text`, `Paragraph`, and `Image` lower through `lower(into:)`.
- [x] Interactions: the `.link(url)` text modifier and generic `.onTap`.
- [x] Images: `ImageSource.resolved` / `.defer`, required sizes, two pipelines.
- [x] `Spacer` node: a fixed width, with an inferred or explicit height.
- [x] Text gradients with line, paragraph, and document lookup scopes.
- [x] `ATR`-prefixed facade aliases.
- [x] Foreground as one fill (color or gradient); engine-drawn underline decorations with color or gradient fills and corners.
- [x] Snapshot tests passing on macOS and the iOS Simulator.
- [x] Commit and push the P0–P3 work.

## P1: Engine skeleton

- [x] `AttributedEngine` (C++20) and `AttributedEngineObjC` (ObjC++ facade, `ATR` prefix) targets.
- [x] Move the IR into the engine: Swift `IR.Builder` forwards each call; op stream, text pool, dedup, validation, and dump are ObjC++/C++.
- [x] ObjC++ engine tests for validation, escaping, dedup, and number formatting.
- [x] C++ style inheritance and the resolved run table.
- [x] Paragraph splitting with UTF-16 ranges for CoreText.
- [x] Test resolved runs against expected snapshots.

## P2: Layout

Design: [layout-and-rendering.md](layout-and-rendering.md).

- [x] Facade converts fonts to `CTFontRef` at `finish`; layout never touches UIKit or AppKit.
- [x] Immutable `ATRTextLayout` computed for a container, on any thread: size, lines, runs, attachment frames.
- [x] Paragraph and line layout on `CTTypesetter`: line and paragraph spacing, alignment, writing direction.
- [x] Attachment runs with fixed and adaptive sizing and alignment against font metrics.
- [x] Measurement through the same layout object (no separate measuring pass).
- [x] Gradient groups with joined rects per lookup scope, and merged underline segments.
- [x] Container limits: maximum height, maximum lines, end truncation with a token.
- [x] Line height modes: typographic (declared fonts) and glyph bounds; ink extents recorded per line.
- [x] Swift `TextContainer` / `TextLayout` with `Sendable` document and layout.
- [x] Shared fallback fonts per document (CoreText would create them per paragraph).
- [x] Incremental relayout when only attachment content sizes change.
- [ ] Exclusion paths.
- [ ] Lazy layout for very long documents (incompatible with `.document` gradient scope).

## P3: Display-only text view

- [x] Swift public `TextView` over the internal `ATRTextDisplayView`; no ObjC exposed.
- [x] Render snapshot with colors resolved on the main thread; synchronous or background drawing into layer bitmaps.
- [x] Opt-in viewport tiling (default tile height 256 pt) driven by the first enclosing scroll view; gradients from the layout's group rects.
- [x] CGContext drawing: text, backgrounds, underline decorations (patterns, double lines, corners), gradient fills for glyphs and underlines that skip emoji by default, images.
- [x] Color re-resolution on appearance change.
- [x] AsyncImage pipeline: `defer` closures after the initial render; redraw, or relayout for adaptive sizes.
- [x] Gestures through hit views: tap (count) and long press (duration), using a factory registry, a policy, bindings, and delegates.
- [x] Hit views follow the viewport and are reused by gesture signature.
- [x] Delegate events with attached values, text ranges, text, location, and rects.
- [x] Basic accessibility label.
- [x] Layout ahead of time: prepared text from any thread, applied synchronously by the view.
- [ ] Relayout on Dynamic Type changes (needs a font table that re-resolves text styles).
- [ ] Richer accessibility (per-link elements).
- [ ] SwiftUI bridge.
- [x] New UIKit demo app (`Demo/AttributedDemo`): home list and a feature showcase; LookinServer for view debugging.
- [x] Demo Stress page: random lifecycle chains and background layout workers, with a hang watchdog.
- [x] Demo Performance page and FPS monitor. The page runs 1K–1M characters, English or mixed scripts, plain, random, or complex styles, sync or async, and times each stage. Launch argument `-benchmark size,script,style,mode`.
- [ ] Exclusion paths and lazy layout (from P2).

Out of scope for now: editing, input methods, and rich selection.
