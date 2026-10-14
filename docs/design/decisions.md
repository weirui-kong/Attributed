# Decisions

## Decision log

Newest last. Entries 1–33 are from 2026-10-13; 34 onward from 2026-10-14.

1. **Rewrite rather than refactor.** Swift DSL on top; an ObjC/C++ engine below; a CoreText-based display component comparable to `UITextView`.
2. **Display only**, with simple taps.
3. **No `NSAttributedString` export and no TextKit backend.** The whole v0.1 implementation, including its SwiftPM layout, tests, and demo, was deleted.
4. **Pure-Swift public API** with no `@objc` exposure. Lower layers prefer ObjC/C++.
5. **`ATR` prefix** for ObjC symbols and for the Swift facade aliases.
6. **Flat op stream plus resource tables** for the IR, with `Attributed.IR.*` naming and `lower(into:)` as the extension point.
7. **Sequential integer IDs** instead of UUIDs, for C struct mapping and a stable dump.
8. **`Link` became a `Text` modifier** (`.link(url)`). **`.onTap` applies to any node.** The hosting view dispatches taps. Spans may wrap whole paragraphs.
9. **Images:** one `Image` node; `ImageSource.resolved` / `.defer` selects the Image or AsyncImage pipeline; a fixed or adaptive size is required.
10. **Text gradients** with line, paragraph, and document modes. Equal configurations share a rect; document mode carries a performance warning; emoji are excluded by default; `TextView.appliesGradientToEmoji` opts them in.
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
32. **Scroll observation lives on `didMoveToWindow`.** The view observes only inside a window and holds the scroll view strongly while observing; no unretained pointers.
33. **Stress page uses a fixed set of font sizes.** UIKit and CoreText cache every distinct font instance for the life of the process. With continuous random sizes, a 40-second run left 76,735 `UICTFont` objects and a 1.58 GB footprint, although no engine or view objects survived. With quantized sizes, the footprint stays between 23 and 38 MB, and `leaks` reports 0 leaks. Callers that generate font sizes dynamically should quantize them for the same reason.
34. **Applying a layout is always synchronous; only bitmap drawing may be asynchronous.**
    - Layout can be computed ahead of time on any thread as `PreparedText`. The view applies it synchronously when its inputs match, and otherwise lays out synchronously itself.
    - The view never has a pending layout. It never shows or reports a layout for other inputs, and `textLayout`, the hit views, and the intrinsic size always agree.
    - A view-level `layoutsAsynchronously` mode existed briefly and was removed for this reason.
    - `rendersAsynchronously` (drawing bitmaps) is the only asynchronous step inside the view.
35. **Fallback fonts come from a per-document cache.** CoreText does not share fallback font objects across typesetters. Measured on 1M mixed-script characters with complex styles, at first draw: 686 MB → 278 MB, and layout 2.3 s → 1.8 s. The cache is per document, not global, so it is freed with the document.
36. **Hit views follow the viewport.** With viewport rendering on, only interaction sets near the visible region get hit views. Hit views are pooled by gesture signature and reused by rebinding interaction IDs, which keeps their recognizers. Hit views stay synchronous on the main thread. A hit view in the middle of recognizing a gesture is never reused.
37. **The demo works around a LookinServer bug.**
    - The bug: LookinServer 1.2.8, the latest release, which upstream master still matches, hides every sublayer before a layer's solo screenshot. For layers over 20,000 pt, it returns early and never shows them again. A long text view (100K characters is about 67,000 pt) then stays blank after one Lookin capture.
    - The workaround: the demo's `LookinWorkaround` wraps `lks_soloScreenshotWithLowQuality:` and shows again whatever it hid. The library is unchanged.
    - Benchmark scroll metrics time main-thread work per frame with run loop observers, from wake-up to sleep after the Core Animation commit. Display-link intervals are quantized to the refresh interval, so they only count dropped frames.
38. **An image arriving relays out only its paragraph.** The previous layout's lines are reused for every other paragraph. This keeps the synchronous apply rule (#34) affordable for adaptive AsyncImages in long text. The Performance page uses fixed image sizes, so loading never relays out at all. In Async mode it also turns on `rendersAsynchronously`, so drawing, and with it image decoding, runs off the main thread. The `.defer` loader itself stays on the main actor by API.

39. **The package targets iOS 15.** A clean build for iOS 15 shows no availability warnings in the library, and the tests pass. No iOS 15 simulator runtime was installed, so this is compile-time compatibility, not a run on iOS 15. The demo stays at iOS 16 because it uses `OSAllocatedUnfairLock`. macOS stays at 13.

40. **`Spacer` is an attachment kind, not a new op.** It reuses U+FFFC ranges, run delegates, and gesture wrapping. Without a height it follows the unsized AsyncImage placeholder rule (adjacent character, else its own font), so a gap never changes line height. With a height it is baseline-aligned like a fixed image.
41. **Public text geometry comes before selection.** `TextLayout` gets public queries: lines, point to offset, offset to caret, range to selection rects, and granularity ranges. Callers need them for their own highlights and anchors. Selection will be built only on them, which proves they are sufficient.
    - Offsets are document-global UTF-16 (the `InteractionEvent.range` space). Coordinates are layout space, which equals the view's bounds.
    - Truncated text is outside `visibleRange` and has no rects. The truncation token maps to no source offset.
    - U+FFFC attachments and spacers are one `character` unit.
    - A point in a line or paragraph gap has no character index and snaps to the nearest line for `closestPosition`.
    - Selection rects use typographic line height. Bidi can split one line into several rects.
    - Lines are read by index, not copied as an array.
    - Design: [text-geometry.md](text-geometry.md).
42. **Text geometry is implemented as `atr::TextGeometry`**, a stateless view over the resolved document and the layout.
    - Paragraphs record their global start.
    - Truncation token runs are marked with a private attribute, and a truncated line's range is the text it shows.
    - Carets and selection rects are clamped to a finite container width, because whitespace at a soft break hangs past it.
    - Word and sentence boundaries use the current locale.
    - `LineMetrics` exposes no ink extent for now.
43. **Test coverage was widened to 235 tests** (macOS and the iOS Simulator). The new tests cover the resolver, the document builder, layout edge cases, incremental relayout, rendering, fallback fonts, DSL lowering, the display view, and the Swift text view. They found two bugs, both fixed:
    - **Empty truncation token.** With an empty token, CoreText keeps one run whose string range still covers the cut text, so a truncated line reported every character as visible. A truncated line's visible end now comes from its last glyph's character, widened to the whole composed sequence.
    - **Truncation token setter.** `ATRTextDisplayView` treats a nil token as U+2026 when matching layouts, but switching between nil and U+2026 still threw the layout away. The setter now compares the normalized tokens.

44. **Text transitions come from the author's other project, re-implemented on this engine's layers.** The motion and parameters are unchanged. The structure follows this repository:
    - Per-glyph atoms are computed in C++ (`atr::glyphAtoms`), since they need CoreText.
    - The bitmap and atoms cross as `ATRGlyphSnapshot`.
    - The host logic lives in `ATRTextDisplayView`.
    - The Metal effect is ObjC++ in the view target. Swift only resolves the effect and maps outcomes.
    - Design: [text-transitions.md](text-transitions.md).
45. **Glyph atoms are designed here, not copied.** The source's tiling code was not available.
    - Keys use an interned font identity (PostScript name and size) plus the glyph ID, so equal glyphs match across documents.
    - Tiles split at the middle of ink gaps and never overlap.
    - Zero-advance glyphs lend their ink to their base glyph.
    - `inkHeight` is at least the cap height, so separators roll as far as digits.
46. **The numeric effect is iOS only for now.** On macOS `begin` returns NO and the text is replaced (`.skipped`). The renderer store still answers `prewarm` (`failed`, then `alreadyFailed`).
47. **Changes to the effect.** Behavior is unchanged except for these:
    - A finish waits for asynchronous bitmaps, so `rendersAsynchronously` shows no blank frame.
    - The overlay is a `CAMetalLayer` view with a display link, not `MTKView`.
    - All tiles of a snapshot are uploaded in one command buffer.
    - Vertex buffers rotate through three, so a frame in flight is never overwritten.
    - The overlay layer uses sRGB.
    - A negative stagger span is clamped to zero.
48. **The comparison with SwiftUI is recorded, not tuned.** The Transitions demo page puts the effect above SwiftUI's own. Frame-by-frame recordings match on roll, blur, scale, direction, stagger, and the odometer rule.
    - Kept glyphs that slide start about 80 ms later in SwiftUI.
    - Trailing glyphs added to a growing number enter near their final place in SwiftUI.
    - Both differences were in the source implementation and are left as they are until the rule behind them is known.
49. **New headers in an umbrella `include/` directory need the explicit module cache cleared.** SwiftPM and Xcode reuse a precompiled module for the target, and it misses the new header ("expected a type"). Delete `.build/out/Intermediates.noindex/SwiftExplicitPrecompiledModules` (for `swift build`) or the same folder under DerivedData (for `xcodebuild`).
50. **The numeric text shader is compiled at build time.**
    - The source shader was compiled from a string at runtime, which takes tens of milliseconds. `ATRNumericText.metal` is now a resource of `AttributedViewObjC`, and SwiftPM and Xcode compile it into the target bundle's `default.metallib`. This was verified with `swift build`, `xcodebuild` for the iOS Simulator, and the Demo app bundle.
    - The cost: anyone building the package needs the Metal Toolchain, a separate download since Xcode 26 (`xcodebuild -downloadComponent MetalToolchain`). Without it the build fails at `CompileMetalFile`.
    - `prewarm` stays, because building the pipeline state still costs milliseconds on first use.

## Open questions

- Text selection on iOS: a read-only `UITextInput` with `UITextInteraction(.nonEditable)` (preferred), or custom handles and menus? See [text-geometry.md](text-geometry.md).
- Default line height mode: `.typographic` (chosen) or `.glyphBounds`?
- Gradient defaults chosen without confirmation:
  - The default scope is `.paragraph`.
  - The rect uses typographic bounds rather than ink bounds.
  - Matching runs need not be adjacent.
  - Gradients apply to `Text` only. Should `Paragraph` get a gradient modifier as well?
- Text transitions: macOS support, migrating `blurReplace`, and whether to adopt SwiftUI's kept-glyph delay and trailing-glyph placement. See [text-transitions.md](text-transitions.md).
- Delete the legacy `docs/api`, `docs/guides`, and `docs/specifications`?
- Underline decorations, chosen without confirmation:
  - Should underlines skip descenders the way native iOS underlines do?
  - Should whole-word underlining (the old `byWord`) return?
  - Should strikethrough join as a second decoration kind?
