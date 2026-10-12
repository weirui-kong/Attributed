# Decisions

## Decision log

Newest last. All entries are from 2026-10-13.

1. **Rewrite rather than refactor.** Swift DSL on top; an ObjC/C++ engine below; a CoreText-based display component comparable to `UITextView`.
2. **Display only**, with simple taps.
3. **No `NSAttributedString` export and no TextKit backend.** The whole v0.1 implementation, including its SwiftPM layout, tests, and demo, was deleted.
4. **Pure-Swift public API** with no `@objc` exposure. Lower layers prefer ObjC/C++.
5. **`ATR` prefix** for ObjC symbols and for the Swift facade aliases.
6. **Flat op stream plus resource tables** for the IR, with `Attributed.IR.*` naming and `lower(into:)` as the extension point.
7. **Sequential integer IDs** instead of UUIDs, for C struct mapping and a stable dump.
8. **`Link` became a `Text` modifier** (`.link(url)`). **`.onTap` applies to any node.** The hosting view dispatches taps. Spans may wrap whole paragraphs.
9. **Images:** one `Image` node; `ImageSource.resolved` / `.defer` selects the Image or AsyncImage pipeline; a fixed or adaptive size is required.
10. **Text gradients** with line, paragraph, and document modes. Equal configurations share a rect; document mode carries a performance warning; emoji are excluded by default behind a future view switch.
11. **Documentation in `docs/`** doubles as the project's memory and is updated with every decision.
12. **Swift is a thin top-level wrapper.** Heavy computation lives in ObjC/C++, and all CoreText interaction is ObjC/C++ only.
13. **The IR moved into the engine.** `IR.Builder` forwards each call to `ATRDocumentBuilder`; the Swift DSL is unchanged. Swift no longer exposes ops or resource tables; `dump()` comes from C++.
14. **`GradientScope` replaces "rendering mode".** It is the lookup space that joins equal gradients into one continuous gradient. The parameter is `scope:`.
15. **ObjC headers never use `NS_ASSUME_NONNULL_BEGIN/END`.** Every pointer is annotated explicitly. The rule is recorded in `AGENTS.md`.
16. **Underlines are engine-drawn decorations**, not platform underlines, so they can use gradients. `UnderlineStyle` became a library struct (lines, pattern, optional thickness) instead of the `NSUnderlineStyle` bit set.
17. **Foreground is one fill (color or gradient)**, and so is the underline fill. This removes the ambiguity of a separate color and gradient where a child's color could not override a parent's gradient. An unset underline fill follows the foreground.
18. **Underline corners**: `.square`, `.radius(r)` clamped to half the thickness, or `.capsule`. They apply per drawn segment (each dash and dot). Equal adjacent underline runs on a line merge into one segment first.
19. **Layout follows YYText's ideas, not its code.** An immutable layout is computed for a given width and contains both the size and the full text layout. CoreText alone makes it safe on background threads.
20. **Viewport tiling is opt-in** on `ATRTextView`, with a default tile height of 256 pt. Tiles draw gradients from the layout's joined group rects (per scope), never from tile-local contents.
21. **Container options** cover maximum height, maximum lines, and a truncation token; exclusion paths and lazy layout come later. All of them are wanted.
22. **Line height modes for tall scripts**: `.typographic` keeps every line at the declared fonts' height (fallback fonts don't grow lines); `.glyphBounds` grows lines to the glyphs' measured ink extent. Ink extents are recorded in both modes so drawing never clips.
23. **Spacing semantics**: `lineSpacing` goes between lines of one paragraph, `paragraphSpacing` between paragraphs, and line height includes leading.
24. **Unsized AsyncImage placeholder**: zero width, and the height of the adjacent character (previous, else next, else the default font).
25. **Naming of the views:** the public Swift view is `Attributed.TextView` (alias `ATRTextView`); the internal ObjC view is `ATRTextDisplayView`.
26. **Viewport tiling follows the first enclosing scroll view**, observed through KVO on iOS and bounds notifications on macOS.
27. **Gestures live on hit views managed by the text view.** Tap takes a count (default 1); long press takes a minimum duration. The recognizer stack is split into an adapter (binding), a factory registry, a policy, and delegates, so new gesture kinds don't touch views.
28. **Interactions carry values.** `onTap` and `onLongPress` take a closure or a `value:` of any type. The delegate receives an `InteractionEvent` with the value, the UTF-16 range and text, the location, and the rects. `Interaction` is only `.action` or `.value`. A link is `.value(url)`. URL values open with the system unless the delegate declines.
29. **Nested interactions** keep the innermost interaction per gesture key (tap count, or long press), so different gestures on the same text coexist.
30. **`Group`** combines nodes without side effects, so several nodes can share one gesture.
31. **Target layout:** the Swift DSL and layout (`AttributedCore`) are split from the views (`AttributedUI`), and the ObjC facade is split into a model target (`AttributedEngineObjC`) and a view target (`AttributedViewObjC`). The C++ engine is grouped by pipeline stage. The view layer uses only the model's public ObjC API.

## Open questions

- Commit the P0–P2 work now?
- Default line height mode: `.typographic` (chosen) or `.glyphBounds`?
- Gradient defaults chosen without confirmation:
  - The default scope is `.paragraph`.
  - The rect uses typographic bounds rather than ink bounds.
  - Matching runs need not be adjacent.
  - Gradients apply to `Text` only. Should `Paragraph` get a gradient modifier as well?
- Delete the legacy `docs/api`, `docs/guides`, and `docs/specifications`?
- Underline decorations, chosen without confirmation:
  - Should underlines skip descenders the way native iOS underlines do?
  - Should whole-word underlining (the old `byWord`) return?
  - Should strikethrough join as a second decoration kind?
