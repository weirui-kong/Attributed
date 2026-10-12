# Layout and Rendering

Status: layout is implemented ([`Sources/Engine/Layout.cpp`](../../Sources/Engine/Layout.cpp), [`Resolve.cpp`](../../Sources/Engine/Resolve.cpp)) and covered by [`Tests/EngineTests/LayoutTests.mm`](../../Tests/EngineTests/LayoutTests.mm) and [`Tests/CoreTests/TextLayoutTests.swift`](../../Tests/CoreTests/TextLayoutTests.swift). Rendering and tiling are design only (P3).

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
- The whole document is laid out once. Tiling (below) only affects drawing.

### Pipeline

1. **Resolve** (once per document, pure C++): the op stream becomes paragraphs of UTF-16 text and maximal runs with fully resolved styles. Equal resolved styles share one index. Attachments become U+FFFC runs of their own.
   - Natural writing direction resolves to the paragraph's first strong character, then left-to-right. This approximates the Unicode first-strong rule with script block ranges, not a full property database.
   - An underline without its own fill takes the foreground fill here.
2. **Typeset** (per container): one `CFAttributedString` per paragraph, used only as CoreText input. It carries the font, kern, writing direction, a run delegate for each attachment, and private attributes that map every `CTRun`, including truncation-token runs, back to its style and attachment.
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

Status: implemented in [`Sources/Engine/Render.cpp`](../../Sources/Engine/Render.cpp) and [`Sources/EngineObjC/ATRRenderSnapshot.mm`](../../Sources/EngineObjC/ATRRenderSnapshot.mm). Pixel-level tests: [`Tests/EngineTests/RenderTests.mm`](../../Tests/EngineTests/RenderTests.mm).

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

Status: implemented. The public view is `Attributed.TextView` (alias `ATRTextView`, [`Sources/Core/TextView.swift`](../../Sources/Core/TextView.swift)). It wraps the internal `ATRTextDisplayView` ([`Sources/EngineObjC/ATRTextDisplayView.mm`](../../Sources/EngineObjC/ATRTextDisplayView.mm)), which does the work. Tests: [`Tests/EngineTests/DisplayViewTests.mm`](../../Tests/EngineTests/DisplayViewTests.mm), [`Tests/CoreTests/TextViewTests.swift`](../../Tests/CoreTests/TextViewTests.swift).

- **Layout:**
  - The display view lays out its document for its own width during the layout pass.
  - `measuredSize(forWidth:)` / `sizeThatFits` use a one-entry measuring cache.
  - `intrinsicContentSize` follows the current width, and size changes invalidate the wrapper's intrinsic size.
- **Drawing** goes into CALayer bitmaps:
  - Synchronous by default; `rendersAsynchronously` draws on a background queue.
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
  - It keeps tiles of `tileHeight` points (default **256**) for the visible region plus one tile of lookahead on each side, and evicts tiles more than one tile beyond that.
- A tile draws every line whose drawn bounds intersect it, clipped to the tile. Drawn bounds include overflowing glyphs, decorations, and attachments. A line that crosses a tile edge is drawn by both tiles.
- **Gradients across tiles:** a tile never computes gradient extents from its own contents. It draws its slice of each run using the group's joined rect from the layout, so a `.paragraph` gradient spanning three tiles stays continuous. `.document` scope works the same way. Its warning only concerns any future lazy layout.

### Gestures

Gestures are split into pieces so that no layer depends on a concrete gesture, as shown in [`ATRGestures.h`](../../Sources/EngineObjC/include/ATRGestures.h):

- **Data:**
  - `ATRGesture` / `atr::Gesture` is plain data in the document.
  - The layout produces **hit regions**: runs with the same interaction set, merged per line, spanning the line's typographic height.
- **Adapter:** `ATRGestureBinding` wraps one platform recognizer. It is the recognizer's target, fires at the gesture's trigger state (tap: ended; long press: began), and reports the interaction ID and location. On macOS it also answers the failure-requirement delegate question.
- **Factory + registry:** `ATRGestureRecognizerFactory` makes bindings for one gesture kind. `ATRGestureRecognizerRegistry` maps kinds to factories, with tap and long-press factories by default. A new kind needs only a factory.
- **Strategy:** `ATRGesturePolicy` wires dependencies among the bindings of one hit view. The default makes each tap wait for higher-count taps to fail.
- **Delegate:** `ATRHitView` covers one interaction set. It hosts that set's bindings, accepts touches only inside its exact regions (`pointInside:` / `hitTest:`), and reports triggers to its `ATRHitViewDelegate`.
- **Manager:** `ATRTextDisplayView` creates, moves, and removes hit views as the layout changes, keyed by interaction set. It injects the registry and policy, and forwards triggers to Swift.

## Swift entry point

```swift
let document = text.lower().document          // IR.Document, Sendable
let layout = document.layout(in: ATRTextContainer(width: 320, maximumNumberOfLines: 3))
layout.size; layout.lineCount; layout.isTruncated
```

`layout(in:)` is synchronous and safe on any thread. `IR.Document` and `TextLayout` are `Sendable`, so a caller can lay out in a detached task and hand the result to the main actor. The Swift alias `ATRTextLayout` and the internal ObjC class `ATRTextLayout` share a name; the ObjC module is never visible to clients, so the two don't collide.

## Open questions

- Should `.glyphBounds` be the default line height mode instead of `.typographic`?
- Is the block-range approximation of first-strong direction enough, or is a full Unicode property table needed?
