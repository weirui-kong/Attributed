# Text Geometry

Status: implemented on `TextLayout`. Engine: [`Geometry.hpp`](../../Sources/AttributedEngine/include/atr/layout/Geometry.hpp) and [`Geometry.cpp`](../../Sources/AttributedEngine/layout/Geometry.cpp); ObjC: `ATRTextLayout`; Swift: [`TextGeometry.swift`](../../Sources/AttributedCore/Layout/TextGeometry.swift). Tests: [`GeometryTests.mm`](../../Tests/AttributedEngineTests/GeometryTests.mm) (44 cases) and [`TextGeometryTests.swift`](../../Tests/AttributedCoreTests/TextGeometryTests.swift). Selection is not implemented yet.

This document describes public position and geometry queries on `TextLayout`. Callers use them for search highlights, popovers anchored to a span, "show more" placement, and exposure tracking. Text selection, which comes later, is built only on these public queries, so a caller can build the same interactions.

## Principles

- **The queries are on `Attributed.TextLayout`, not on the view.** A layout is immutable and `Sendable`, so every query is safe on any thread. Queries also work on a `PreparedText` before any view exists, for example while preparing a list cell.
- **Index space:** document-global UTF-16 offsets and `NSRange`. Paragraphs are joined by one newline, and each attachment is one U+FFFC. This is the same space as `InteractionEvent.range` and `ResolvedDocument::interactionRanges`.
- **Coordinates:** layout space, with the origin at the top left and y growing downward. The text view has no insets, so layout space equals the view's bounds. If the view ever gains insets, it adds conversion methods at that point.
- **Value types only.** No CoreText or `ATR*` type appears in the public API.
- **Characters and lines only.** Runs and glyphs stay private, so the engine can change how it represents them.
- The computation is C++ (hard constraint: anything touching CoreText is never Swift). The ObjC facade passes C structs through, as `hitRegionAtIndex:` does. Swift wraps them in value types.

## Public API

```swift
public extension Attributed {
    // Which visual place an offset means when it has two: the end of one
    // line and the start of the next at a soft break, or the two sides of a
    // bidi boundary. Upstream belongs to the preceding character.
    enum TextAffinity: Sendable {
        case upstream
        case downstream
    }

    struct TextPosition: Hashable, Sendable {
        public var offset: Int
        public var affinity: TextAffinity
    }

    enum TextGranularity: Sendable {
        // One grapheme cluster: never splits a composed character sequence
        // or an emoji ZWJ sequence.
        case character
        case word
        case sentence
        case line
        // Excludes the newline separator.
        case paragraph
    }

    struct LineMetrics: Sendable {
        public let index: Int
        public let paragraphIndex: Int
        // Document-global; for a truncated line, only the text it shows.
        public let range: NSRange
        // Typographic frame: origin x, line top, used width, line height.
        public let frame: CGRect
        public let baseline: CGFloat
        public let isTruncated: Bool
    }

    struct SelectionRect: Sendable {
        public let rect: CGRect
        public let lineIndex: Int
        public let isRightToLeft: Bool
        public let containsStart: Bool
        public let containsEnd: Bool
    }
}

public extension Attributed.TextLayout {
    // Text
    var textLength: Int { get }
    func text(in range: NSRange) -> String
    // The part of the text that is drawn; excludes text cut by truncation
    // or line and height limits.
    var visibleRange: NSRange { get }

    // Lines (lineCount already exists)
    func line(at index: Int) -> Attributed.LineMetrics
    func lineIndex(atY y: CGFloat) -> Int?
    func lineIndex(containing position: Attributed.TextPosition) -> Int?
    // Lines whose frames intersect `rect` vertically, for viewport work.
    func lineIndexes(in rect: CGRect) -> Range<Int>

    // Hit testing
    func characterIndex(at point: CGPoint) -> Int?
    func closestPosition(to point: CGPoint) -> Attributed.TextPosition

    // Geometry
    func caretRect(for position: Attributed.TextPosition) -> CGRect
    // `rect` limits the result to lines it intersects; nil means all lines.
    func selectionRects(for range: NSRange, in rect: CGRect? = nil) -> [Attributed.SelectionRect]
    func boundingRect(for range: NSRange) -> CGRect

    // Granularity
    func range(enclosing offset: Int, granularity: Attributed.TextGranularity) -> NSRange?
}
```

Lines are read one at a time instead of as an array. A 1M-character document has thousands of lines, and copying them all for every query is wasteful.

Whole-document text is read through `text(in:)` rather than a `text: String` property for the same reason.

## Semantics

1. **Truncation.** `visibleRange` covers only drawn text.
   - For a range that is not visible, `selectionRects` returns nothing for the hidden part.
   - A caret at a hidden offset sits right before the truncation token.
   - The token ("…" by default) maps to no source offset. A point on the token resolves to the last visible offset of that line.
2. **Attachments and spacers** (U+FFFC) are one UTF-16 unit and one `character` unit. Their selection rect is the attachment frame widened to the line's typographic height. A caret never sits inside one.
3. **Gaps between lines.** `lineSpacing` and `paragraphSpacing` leave gaps between lines.
   - A point in a gap is not on a character: `characterIndex(at:)` returns nil.
   - `closestPosition(to:)` snaps to the nearest line, as system text views do.
   - A point left or right of a line resolves to that line's visual start or end.
4. **Container edge.** Whitespace at a soft break hangs past the container width. Carets and selection rects are clamped to a finite container width, so they never leave the view.
5. **Selection rect height** is the line's typographic height (ascent + descent + leading), not its ink extent, so rects of adjacent lines meet without overlapping. In `.glyphBounds` mode the typographic height already contains the glyphs.
6. **Bidi.** In mixed-direction text, a logical range can cover several visually separate pieces of one line, so a line can return more than one `SelectionRect`. The pieces come from each run's string indices and direction, not from two caret offsets.
7. **Soft line breaks.** At an offset where a line wraps, `.upstream` is the end of the earlier line and `.downstream` is the start of the next one. Elsewhere, at a bidi boundary, the affinity picks the side whose run the adjacent character belongs to.

## Engine implementation

- **Paragraph starts.** `Line.location` is paragraph-local. Each `ResolvedParagraph` records its global `start`, so conversion is one addition, and `ResolvedDocument::text` copies only the requested range.
- **Truncated lines.** Token runs carry a private `ATRTruncationToken` attribute and are flagged `LineRun::truncationToken`. A truncated line's `length` is the text it shows before the token, which can be shorter or longer than where the line first broke. The end comes from glyph string indices rather than run string ranges: with an empty token, CoreText keeps a run whose range still covers the cut text.
- `atr::TextGeometry` holds only references to the resolved document and the layout, so each ObjC call makes one cheaply.
- **Line lookup by y:** binary search over line tops. **Lookup by offset:** binary search over line ranges.
- **Point to offset:** `CTLineGetStringIndexForPosition` after the line is found, then clamped to grapheme boundaries and to the visible part. A truncation-token run is recognized by the private attributes that already map every run back to its style.
- **Range to rects:** walk the line's runs in visual order. Intersect each run's string indices with the range, and use `CTRunGetStatus` for direction. Adjacent pieces on one line merge.
- **Caret:** `CTLineGetOffsetForStringIndex` (primary or secondary offset, chosen by affinity).
- **Granularity:**
  - `character`: `CFStringGetRangeOfComposedCharactersAtIndex`.
  - `word` and `sentence`: `CFStringTokenizer` over the paragraph text.
  - `line`: the line's range. `paragraph`: the paragraph's range.
- Tests cover the index space, line lookup, gaps, soft-break affinity, grapheme clusters and emoji, right-to-left and mixed text, attachments and spacers, truncation (token, hidden offsets, empty paragraphs, height limits), every granularity, an empty document, overflowing ranges, incremental relayout, and concurrent queries.

## Later: text selection

Selection is built on the queries above. The planned shape is below; it is not decided yet.

- **iOS:** `ATRTextDisplayView` adopts a read-only `UITextInput` and installs `UITextInteraction(for: .nonEditable)` (iOS 13+). This gives system handles, the loupe, the edit menu, and word selection on iOS 15.
- The highlight is drawn in its own layer, never into tile bitmaps. Otherwise viewport tiling and `rendersAsynchronously` would redraw tiles on every drag.
- A long press on text that has an `onLongPress` interaction needs a priority rule.
- Copying is plain text only (no `NSAttributedString` export).
- A relayout clamps the selection to the new layout.
- macOS needs its own implementation (mouse drag, I-beam cursor, context menu).

## Choices made during implementation

- Word and sentence boundaries use the current locale (`CFLocaleCopyCurrent`). A per-document locale can come later.
- `LineMetrics` exposes only the typographic frame. The ink extent stays internal until a caller needs it.
