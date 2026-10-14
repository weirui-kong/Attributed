# Text Transitions

Status: `numericText` is implemented on iOS. On macOS the text is simply replaced. Engine: [`GlyphAtoms.hpp`](../../Sources/AttributedEngine/include/atr/layout/GlyphAtoms.hpp) and [`GlyphAtoms.cpp`](../../Sources/AttributedEngine/layout/GlyphAtoms.cpp). ObjC: [`ATRGlyphSnapshot`](../../Sources/AttributedEngineObjC/include/ATRGlyphSnapshot.h), [`ATRTextTransition.h`](../../Sources/AttributedViewObjC/include/ATRTextTransition.h), [`ATRNumericTextTransition.mm`](../../Sources/AttributedViewObjC/ATRNumericTextTransition.mm) with its shader [`ATRNumericText.metal`](../../Sources/AttributedViewObjC/ATRNumericText.metal), and the host logic in `ATRTextDisplayView`. Swift: [`TextTransition.swift`](../../Sources/AttributedUI/TextTransition.swift) and `TextView.setText(_:transition:completion:)`. Tests: [`GlyphSnapshotTests.mm`](../../Tests/AttributedEngineTests/GlyphSnapshotTests.mm) and [`TextTransitionTests.mm`](../../Tests/AttributedViewObjCTests/TextTransitionTests.mm). Demo: the Transitions page shows each sample above SwiftUI's own `.contentTransition(.numericText())`.

The effect was migrated from another project of the author's and re-implemented on this engine's layers. Its parameters and motion are unchanged.

## Public API

```swift
textView.setText(newText, transition: .numericText(.upward)) { outcome in
    // .finished, .superseded, .interrupted, or .skipped
}

// Optional, on a background queue: builds the Metal pipeline ahead of time.
_ = Attributed.TextTransition.prewarmNumericText()
```

- `numericText(_ direction: NumericTextDirection = .downward, anchoring: NumericTextAnchoring = .screen)`.
  - `.downward`: new glyphs come in from above, and old ones leave downward. SwiftUI shows this for `numericText(countsDown: false)` and for a decreasing `numericText(value:)`.
  - `.screen` anchoring: a kept glyph slides from its place on screen. Use it for a view that resizes or re-aligns because of its text.
  - `.view` anchoring: glyphs move with the view at once. Use it for a view that is moved for other reasons while its text changes.
- A `setText(_:transition:)` while one runs carries the running effect on from where it is, if it is the same kind.
- A plain `text` assignment while one runs shows the new text at once (`.interrupted`).
- The transition is skipped (`.skipped`) in these cases: no window, viewport rendering is on, the bounds are empty, or the effect cannot run (macOS, no Metal).
- The completion is called once on the main thread, unless the view goes away first.

## Layers

| Layer | Piece | Job |
| --- | --- | --- |
| C++ | `atr::glyphAtoms` | One atom per glyph or attachment, line by line and left to right: a key (interned font identity and glyph ID), the pen position, the advance, a tile, the midline, the ink height, and whether it is numeric |
| ObjC model | `ATRGlyphSnapshot` | Draws a layout once into a BGRA bitmap over the bounds plus everything drawn beyond them, and carries the atoms |
| ObjC view | `ATRTextDisplayView` | The host: it takes snapshots, hides its own layers, and hands new content to the effect at the next layout pass |
| ObjC view | `ATRNumericTextTransition` | The effect: diff, springs, anchoring, and a Metal overlay |
| Swift | `TextTransition`, `TextView.setText(_:transition:completion:)` | A factory that resolves the effect, value types, and outcome mapping |

### Atoms

- **Key.** The font identity comes from the PostScript name and point size, interned per process. It does not come from the `CTFont` object, because every document converts its fonts on its own, and the same digit in the old and new text must compare equal. Attachments use font 0 and their attachment ID.
- **Tiles never overlap and sit on the pixel grid**, so cutting the bitmap into tiles loses and duplicates nothing.
  - Horizontally, the boundary between two neighbors is the middle of the gap between their ink. Where their ink overlaps, it is the second glyph's pen position.
  - Whitespace owns its advance.
  - A zero-advance glyph, such as a combining mark, lends its ink to the glyph it sits on and gets an empty tile.
  - The outer edges cover the runs, plus two pixels for antialiasing.
  - Vertically, a line covers its drawn extent, glyph ink, and underlines. Lines whose extents overlap are split at the upper line's typographic bottom.
- **`inkHeight`** is the glyph's ink height, but at least the font's cap height. Blur and offset scale with it, so "." and "," roll as far as the digits next to them.
- **`midline`** is the middle of the font's typographic box, the point a glyph scales around.
- **`numeric`** marks a decimal digit, or a "." or "," next to one.

### Host

- `setDocument:layout:transition:completion:`:
  1. Resolves the effect from the running one.
  2. If the effect is new, it ends the old one (`.superseded`), takes a snapshot of the content on screen, and calls `begin`. If `begin` succeeds, it hides the tile layers.
  3. Replaces the document.
  4. Schedules a layout pass.
- New content is handed over only during layout (`transitionToSnapshot:`). Before that, the bounds it is laid out for are unknown, because the intrinsic size can change.
- Each later layout or content change while the effect runs (width, appearance, an image arriving) goes through `relayoutWithSnapshot:`.
- When the effect calls its completion, the host waits for the tile controller's asynchronous bitmaps (`performWhenRendered:`) before it cancels the effect and shows its own layers. With `rendersAsynchronously` there is no blank frame.
- Leaving the window, or turning on viewport rendering, interrupts the transition.

### Effect

The effect follows SwiftUI's numericText content transition.

- **Diff.** The effect keeps the longest common prefix and suffix of keys and replaces everything between them. Like an odometer, once a change reaches into a number, every digit after it in that number rolls too.
- **Per glyph,** four tracks driven by springs:
  - **presence** (mass 1, stiffness 344, damping 37) drives alpha, scale (51/128 → 1), and blur (σ = (1 − p) · 0.25 · inkHeight / 2);
  - **shift** (mass 2, stiffness 470, damping 34) drives the vertical offset of 19/32 · inkHeight;
  - **x and y** follow the presence spring.
- **Stagger.** Changed glyphs start 0.15 s apart, spread over at most 0.2 s, mirrored for right-to-left text.
- **Stretch.** While the replaced range sits on one line before and after, outgoing glyphs travel to the matching place in the new range, and incoming ones come from the matching place in the old range. Otherwise they fade in place.
- **Anchoring.**
  - Each position track has two ends. An end either rides with the host (host coordinates) or is fixed in the anchor's coordinates. The anchor is the nearest scroll view, else the window.
  - The host's origin is read every frame. Presentation layers are used, except on the frame that goes out with a transaction.
- **Drawing.**
  - A `CAMetalLayer` overlay is added to the host.
  - Its first frame is rendered in `displayLayer:` with `presentsWithTransaction`, so it lands in the same Core Animation commit that hides the host's layers.
  - Later frames come from a display link.
  - Each tile becomes one mipmapped texture with an 8 px transparent border, and all tiles of one snapshot are uploaded in one command buffer.
  - The fragment shader blurs with a 9 × 9 Gaussian over 3σ and picks the mip level from the tap spacing.
  - Vertex data rotates through three buffers, so a frame in flight is never overwritten.
  - The layer's color space is sRGB, which matches the snapshot.
- **Shader.** `ATRNumericText.metal` is a resource of `AttributedViewObjC`. The build compiles it into `default.metallib` in the target's bundle, and the effect loads it with `newDefaultLibraryWithBundle:`. Building the package needs the Metal Toolchain (`xcodebuild -downloadComponent MetalToolchain`).
- **Prewarm.** The pipeline state still takes milliseconds on first use, because the driver turns the library into GPU code. One pipeline is shared:
  - A first use builds it on its own thread. The first stored result wins, failure included.
  - `prewarm` returns `alreadyInProgress` instead of building twice.

## Compared with SwiftUI

The Transitions demo page was recorded on the iOS 26 simulator and compared frame by frame against SwiftUI's own transition.

- Glyph roll, blur, scale, direction, stagger, and the odometer rule match.
- **Kept glyphs** that slide because the changed range changed width (" unread messages" in the sentence sample) start about 80 ms later in SwiftUI. After that their curve is close to the presence spring. Ours start with the roll.
- **Trailing glyphs** that a growing number adds enter near their final place in SwiftUI. Ours stretch from the old range.

Both differences are unchanged from the source implementation and are left as they are until the rule behind them is known.

## Open questions

- macOS: an `NSView` overlay and the AppKit anchor (the enclosing `NSScrollView`'s clip view).
- `blurReplace`: the source project has one; not migrated yet.
- The kept-glyph delay and the trailing-glyph placement described above.
