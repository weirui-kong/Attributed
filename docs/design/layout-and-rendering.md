# Layout and Rendering

Status: layout is implemented ([`Sources/AttributedEngine/layout/Layout.cpp`](../../Sources/AttributedEngine/layout/Layout.cpp), [`Resolve.cpp`](../../Sources/AttributedEngine/resolve/Resolve.cpp)) and covered by [`Tests/AttributedEngineTests/LayoutTests.mm`](../../Tests/AttributedEngineTests/LayoutTests.mm) and [`Tests/AttributedCoreTests/TextLayoutTests.swift`](../../Tests/AttributedCoreTests/TextLayoutTests.swift). Rendering and tiling are design only (P3).

The ideas come from YYText: an immutable layout computed for a container, then drawn separately, possibly off the main thread. They are adapted, not copied.

## Layout

```
ATRDocument (immutable) + width ──compute──► ATRTextLayout (immutable)
                                              ├ size (width used, total height)
                                              ├ paragraphs → lines → runs (UTF-16 ranges, origins, bounds)
                                              ├ attachment frames
                                              ├ decoration segments (merged underlines)
                                              └ gradient groups (joined rects)
```

- A layout is computed for a given width and contains both the measured size and the full text layout. A view displays a layout; measuring and displaying share the same object, so text is never laid out twice for one width.
- All computation is C++ on CoreText (`CTTypesetter` / `CTLine`); see the hard constraints. CoreText is thread-safe for this use, so a layout can be computed on any thread. No UIKit or AppKit text class is involved.
- To keep layout free of UIKit/AppKit:
  - The facade converts fonts to `CTFontRef` when the document is finished. `UIFont`/`NSFont` are toll-free bridged with `CTFont`, so this is a cast plus a retain.
  - Layout never touches colors. Colors are resolved only for drawing.
  - Attachments contribute only their descriptor sizes. `defer` closures are `@MainActor` and are never called during layout.
- A Dynamic Type change re-resolves the font table and produces a new layout. An appearance change keeps the layout and only redraws.
- An adaptive AsyncImage with no size yet lays out as a zero-width placeholder as tall as the adjacent character: the text right before it, else the text right after it, else the default font. The placeholder sits on the baseline like that character, so the line keeps its height until the image arrives.
- When an AsyncImage arrives: a fixed size only redraws; an adaptive size needs a new layout, which takes the loaded size through `Container::attachmentContentSizes`.
- **Incremental relayout:** `computeLayout` can take the previous layout of the same document, and the display view always passes its current one.
  - Each `Layout` records its `Container`.
  - Reuse applies when only attachment content sizes differ, with no line or height limit, and when the previous layout was not truncated.
  - Only paragraphs holding a changed attachment are typeset and broken again. Every other paragraph's lines are copied (same `CTLine` objects) and shifted to their new top.
  - Annotation still runs over all lines. The typesetter measures attachments on demand, so reused paragraphs never need typesetting.
  - Measured on 1M characters in release: 1305 ms → 39 ms. Tests: [`IncrementalLayoutTests.mm`](../../Tests/AttributedEngineTests/IncrementalLayoutTests.mm) check the result equals a full layout.
- The whole document is laid out once. Tiling (below) only affects drawing.

### Pipeline

The C++ layout is split by stage under `Sources/AttributedEngine/layout/`, sharing a read-only `LayoutContext`:

| File | Stage |
| --- | --- |
| `Typesetter` | Builds each paragraph's CoreText input on first use: attributes, attachment measurement, run delegates, the unsized-AsyncImage placeholder |
| `LineBreaker` | Breaks and places lines: spacing, line height modes, alignment, container limits, truncation |
| `LayoutAnnotator` | Runs in visual order, attachment frames, gradient groups, underline segments, hit regions, size |
| `Layout.cpp` | `computeLayout` wires the three stages together |


1. **Resolve** (once per document, pure C++): the op stream becomes paragraphs of UTF-16 text and maximal runs with fully resolved styles. Equal resolved styles share one index. Attachments become U+FFFC runs of their own.
   - Natural writing direction resolves to the paragraph's first strong character, then left-to-right. This approximates the Unicode first-strong rule with script block ranges, not a full property database.
   - An underline without its own fill takes the foreground fill here.
2. **Typeset** (per container): one `CFAttributedString` per paragraph, used only as CoreText input. It carries the font, kern, writing direction, a run delegate for each attachment, and private attributes that map every `CTRun`, including truncation-token runs, back to its style and attachment.
   - **Fallback fonts are assigned explicitly.** CoreText creates its own fallback font objects for every typesetter. With one typesetter per paragraph, that means thousands of copies of the same few fonts at tens of kilobytes each. The typesetter finds characters the run's font cannot draw. It widens them to whole composed character sequences and assigns the font `CTFontCreateForString` picks, taken from the document's `FallbackFontCache` (thread-safe; one instance per font and fallback). Line widths are unchanged.
   - Measured on 5,000 mixed-script paragraphs: 410 MB → 85 MB, and 965 ms → 615 ms.
3. **Break lines** with `CTTypesetterSuggestLineBreak` against the container width.
4. **Place lines** top to bottom:
   - `lineSpacing` goes between lines of one paragraph; `paragraphSpacing` goes between paragraphs.
   - A line's height is ascent + descent + leading. An empty paragraph still produces a line sized by its paragraph font.
   - Alignment uses CoreText flush offsets. Natural alignment follows the resolved direction. Justified paragraphs justify every line except the last. An infinite width disables wrapping and alignment.
5. **Collect runs** in visual order, then derive attachment frames, gradient groups, and underline segments.
6. **Measure**: the used width is the widest line, excluding trailing whitespace. The height is the last line's bottom. Neither is rounded.

### Container

| Option | Default | Behavior |
| --- | --- | --- |
| `width` | required | Positive; `.infinity` disables wrapping and alignment |
| `maxHeight` | `.infinity` | Lines that would end below it are dropped |
| `maximumNumberOfLines` | 0 (unlimited) | Lines past it are dropped |
| `truncationToken` | `…` | When content is dropped, the last kept line is truncated at its end with the token, styled like the character before it. If that line ends its paragraph and the content cut is a later paragraph, the token is appended after the line's own text. |
| `lineHeightMode` | `.typographic` | See below |

Planned container options: exclusion paths, and lazy layout for very long documents.

### Line height modes

Scripts such as Thai and Myanmar stack marks above and below the base glyph, beyond the font's ascent and descent. UIKit sizes such lines with font metrics, so measured and drawn sizes disagree. The engine measures every glyph's bounding box (`CTFontGetBoundingRectsForGlyphs` plus the glyph positions, which carry mark offsets) and records each line's **ink extent** in every mode.

- `.typographic` (default height): line metrics come from the **declared** fonts, even where CoreText substitutes a fallback font. Every line keeps the default height, and tall glyphs may overflow into neighboring lines. Measured at 16 pt on macOS, a Myanmar line is 18.8 pt tall while its marks reach 5 pt below it.
- `.glyphBounds` (actual height): a line grows to contain its ink extent, so a line that contains Myanmar text becomes taller (24.6 pt in the same measurement).
- Either way, drawing and tiling use the drawn extent (the typographic frame united with the ink extent), so overflowing glyphs are never clipped.

### Default font

Text without a font uses the body text style on iOS and the system font size on macOS. The facade supplies this font outside the font table, so it doesn't change resource indices.

### Gradient groups

While laying out, the engine groups runs that use an equal gradient (by `GradientRef`, scope included) within each scope instance: one CTLine for `.line`, one paragraph for `.paragraph`, the whole document for `.document`. Each group stores the union of its runs' typographic bounds. Glyph fills and underline fills with the same ref join the same group. Drawing reads these rects and never recomputes them.

### Decorations

Underline segments are produced during layout. Adjacent runs on one line with an equal underline and fill are merged into one segment, then corners are applied, so run boundaries never show caps. Thickness and position fall back to the font's underline metrics.

## Rendering

Status: implemented in [`Sources/AttributedEngine/render/Render.cpp`](../../Sources/AttributedEngine/render/Render.cpp) and [`Sources/AttributedEngineObjC/ATRRenderSnapshot.mm`](../../Sources/AttributedEngineObjC/ATRRenderSnapshot.mm). Pixel-level tests: [`Tests/AttributedEngineTests/RenderTests.mm`](../../Tests/AttributedEngineTests/RenderTests.mm).

- `ATRRenderSnapshot` bundles a layout, the colors resolved for one appearance on the main thread, and the attachment images. Drawing it is then safe on any thread.
- The renderer draws in layout coordinates (top-left origin, y down) with a flipped text matrix, in passes:
  1. **backgrounds**, so no background covers a neighbor's overflowing glyphs;
  2. **attachments**;
  3. **glyphs**;
  4. **decorations**.
- Glyph fills:
  - **Color:** the run's fill color through `kCTForegroundColorFromContextAttributeName`, so layout stays color-independent.
  - **Gradient:** the glyphs are used as a clip (`kCGTextClip`), then the gradient is drawn over the group's joined rect.
  - **Color glyphs (emoji):** keep their own colors by default. When opted in, they are tinted by compositing the gradient with `kCGBlendModeSourceIn` in a transparency layer, because they have no outlines to clip with.
- Underlines:
  - Each merged segment is cut into pattern pieces, in multiples of the thickness: dot `1,1`, dash `3,2`, dash-dot `3,2,1,2`, dash-dot-dot `3,2,1,2,1,2`.
  - Each piece is a rounded rect, with its radius clamped to half its width and height.
  - Double lines sit one thickness above and below the center.
  - Gradient underlines clip to the pieces and draw the group's gradient.
- Images are drawn in their attachment frames, flipped for CoreGraphics. A fixed size stretches the image.

## Text view

Status: implemented. The public view is `Attributed.TextView` (alias `ATRTextView`, [`Sources/AttributedUI/TextView.swift`](../../Sources/AttributedUI/TextView.swift)). It wraps the internal `ATRTextDisplayView` ([`Sources/AttributedViewObjC/ATRTextDisplayView.mm`](../../Sources/AttributedViewObjC/ATRTextDisplayView.mm)), which does the work. Tests: [`Tests/AttributedViewObjCTests/DisplayViewTests.mm`](../../Tests/AttributedViewObjCTests/DisplayViewTests.mm), [`Tests/AttributedUITests/TextViewTests.swift`](../../Tests/AttributedUITests/TextViewTests.swift).

- **Structure:** `ATRTextDisplayView` only assembles internal helpers (private headers in `Sources/AttributedViewObjC/`):
  - `ATRTileController`: the surface and tile layers, content generations, synchronous or background drawing.
  - `ATRScrollObserver`: the first enclosing scroll view and the visible region.
  - `ATRHitViewManager`: hit views per interaction set, built with the injected registry and policy.
- **Layout:**
  - The display view lays out its document for its own width during the layout pass.
  - A layout prepared ahead of time (`setDocument:layout:`, Swift `setText(_ prepared:)`) is installed as is when it matches the view's inputs: document, width, maximum lines, line height mode, truncation token (nil means U+2026), and loaded image sizes. `ATRTextLayout` records the last two for this check. The view drops the prepared layout once it is installed or an input changes, so it never keeps a stale large layout.
  - Applying a layout is always synchronous. To keep layout off the main thread, prepare it ahead of time and hand it over; only bitmap drawing can be asynchronous inside the view.
  - `measuredSize(forWidth:)` / `sizeThatFits` use a one-entry measuring cache.
  - `intrinsicContentSize` follows the current width, and size changes invalidate the wrapper's intrinsic size.
- **Drawing** goes into CALayer bitmaps:
  - Synchronous by default. `rendersAsynchronously` draws, and decodes images, on a background queue. It stays off by default because a tile scrolled into view is blank until its bitmap arrives, so fast scrolling can briefly show blank areas. The API comments say so.
  - Results are tagged with a content generation, and stale ones are dropped.
  - Appearance changes re-resolve colors and redraw; scale changes redraw.
  - In AppKit's flipped layer tree, contents render upside down. Any layer reporting `contentsAreFlipped` gets a vertical counter-flip.
- **Swift wrapper**, which keeps only Swift-only state:
  - It lowers `text`, installs resolved images immediately, and calls `defer` closures on the next main-queue turn (dropped if the text changed meanwhile).
  - It maps interaction IDs back to closures and values, and builds delegate events.
  - It sets an accessibility label from the document's plain text.

### Viewport tiling

- Off by default: the view draws the whole layout as one surface.
- `isViewportRenderingEnabled` turns it on.
  - The display view finds the **first enclosing scroll view**: the nearest `UIScrollView` ancestor, or `enclosingScrollView` on macOS.
  - It observes the scroll position: KVO on `contentOffset` on iOS, clip-view bounds notifications on macOS.
  - Observation starts and stops only when the view moves to a window (`didMoveToWindow`), or when viewport rendering is switched while already in one. Outside a window nothing is observed. While observing, the scroll view is held strongly: a window's hierarchy retains it anyway, and leaving the window is reported to every descendant, so there is no retain cycle and observation is always removed from a live object. An ancestor moved between scroll views within the same window is picked up only at the next window move.
  - It keeps tiles of `tileHeight` points (default **256**) for the visible region plus one tile of lookahead on each side, and evicts tiles more than one tile beyond that.
- A tile draws every line whose drawn bounds intersect it, clipped to the tile. Drawn bounds include overflowing glyphs, decorations, and attachments. A line that crosses a tile edge is drawn by both tiles.
- **Gradients across tiles:** a tile never computes gradient extents from its own contents. It draws its slice of each run using the group's joined rect from the layout, so a `.paragraph` gradient spanning three tiles stays continuous. `.document` scope works the same way. Its warning only concerns any future lazy layout.

### Gestures

Gestures are split into pieces so that no layer depends on a concrete gesture, as shown in [`ATRGestures.h`](../../Sources/AttributedViewObjC/include/ATRGestures.h):

- **Data:**
  - `ATRGesture` / `atr::Gesture` is plain data in the document.
  - The layout produces **hit regions**: runs with the same interaction set, merged per line, spanning the line's typographic height.
- **Adapter:** `ATRGestureBinding` wraps one platform recognizer. It is the recognizer's target, fires at the gesture's trigger state (tap: ended; long press: began), and reports the interaction ID and location. On macOS it also answers the failure-requirement delegate question.
- **Factory + registry:** `ATRGestureRecognizerFactory` makes bindings for one gesture kind. `ATRGestureRecognizerRegistry` maps kinds to factories, with tap and long-press factories by default. A new kind needs only a factory.
- **Strategy:** `ATRGesturePolicy` wires dependencies among the bindings of one hit view. The default makes each tap wait for higher-count taps to fail.
- **Delegate:** `ATRHitView` covers one interaction set. It hosts that set's bindings, accepts touches only inside its exact regions (`pointInside:` / `hitTest:`), and reports triggers to its `ATRHitViewDelegate`.
- **Manager:** `ATRHitViewManager` creates, moves, hides, and reuses hit views, keyed by interaction set. It injects the registry and policy. `ATRTextDisplayView` drives it and forwards triggers to Swift. All of this runs synchronously on the main thread.
  - Without viewport rendering, every set has a visible hit view.
  - With viewport rendering, only sets with a region in the visible region plus one tile above and below (the tile prefetch range) get a hit view, holding only those regions. The manager sorts the layout's hit regions by `minY` once per layout, so each scroll update is a binary search plus the visible regions. An unchanged rect costs nothing.
  - A hit view whose set leaves the range is hidden and pooled by **gesture signature**: the kind and parameters of each binding, in the set's order. A set entering with the same signature takes it over. Recognizers and the policy's dependencies stay intact; only the bindings' `interaction` and the hit view's `interactionSet` change. A hit view whose recognizer is past its possible state is neither moved nor reused until it finishes.
  - The pool is cleared with the document, registry, or policy.
  - Measured on 1M characters with 1,272 interactions: 2 live hit views instead of about 2,100, and first display on the main thread 57 → 12 ms.

## Swift entry point

```swift
let document = text.lower().document          // IR.Document, Sendable
let layout = document.layout(in: ATRTextContainer(width: 320, maximumNumberOfLines: 3))
layout.size; layout.lineCount; layout.isTruncated
```

`AttributedText.prepare(in:)` lowers and lays out in one step on any thread. It returns a `Sendable` `PreparedText` that `TextView.setText(_:)` shows without laying out again when the container matches the view.

`layout(in:)` is synchronous and safe on any thread. `IR.Document` and `TextLayout` are `Sendable`, so a caller can lay out in a detached task and hand the result to the main actor. The Swift alias `ATRTextLayout` and the internal ObjC class `ATRTextLayout` share a name; the ObjC module is never visible to clients, so the two don't collide.

## Open questions

- Should `.glyphBounds` be the default line height mode instead of `.typographic`?
- Is the block-range approximation of first-strong direction enough, or is a full Unicode property table needed?
