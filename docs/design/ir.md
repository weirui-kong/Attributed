# IR

Status: implemented. The document lives in engine memory: storage, validation, and dump are C++ ([`Sources/Engine/`](../../Sources/Engine/)), resource deduplication is ObjC++ ([`Sources/EngineObjC/`](../../Sources/EngineObjC/)), and Swift ([`Sources/Core/IR/`](../../Sources/Core/IR/)) only forwards builder calls. Covered by [`Tests/CoreTests/`](../../Tests/CoreTests/) and [`Tests/EngineTests/`](../../Tests/EngineTests/).

## Flow

```
Swift DSL node ──lower(into:)──► IR.Builder (Swift, thin)
                                   │ one ObjC call per builder call, C structs only
                                   ▼
                                 ATRDocumentBuilder (ObjC++)
                                   ├ font / color tables, deduplicated by isEqual
                                   └ atr::DocumentBuilder (C++)
                                       op stream, UTF-16 text pool, style tables,
                                       gradient dedup, structural validation
                                   ▼
                                 ATRDocument ──► atr::Document (immutable)
```

Swift keeps only what must be Swift: interaction closures and URLs, and image sources, which include the `defer` closures. `IR.LoweredText` pairs the engine document with those tables and exposes `interaction(for:)` and `imageSource(for:)`.

## Engine storage (`atr::Document`)

```cpp
std::vector<Op> ops;               // Op { kind, first, second }
std::u16string text;               // all text, UTF-16
std::vector<TextStyle> textStyles;
std::vector<ParagraphStyle> paragraphStyles;
std::vector<Gradient> gradients;   // deduplicated
std::vector<AttachmentDescriptor> attachments;   // index = AttachmentID
```

| Op kind | `first` | `second` |
| --- | --- | --- |
| `BeginParagraph` | paragraph style index | text style index |
| `EndParagraph` | — | — |
| `PushSpan` | text style index | interaction ID or `kNoInteraction` |
| `PopSpan` | — | — |
| `Text` | UTF-16 offset in the text pool | UTF-16 length |
| `Attachment` | attachment ID | — |

Why a flat op stream instead of a tree: it expresses arbitrary nesting without changing shape, stays one contiguous array with no recursion, and is consumed with a simple style stack.

## Invariants

`atr::DocumentBuilder` returns a `BuildStatus` for every call, and the ObjC++ facade raises `NSInternalInconsistencyException` on any status other than `Ok`. The rules:

1. Scopes nest strictly (`MismatchedScope`), and paragraphs never nest (`NestedParagraph`).
2. `text` and `attachment` appear only inside a paragraph (`ContentOutsideParagraph`).
3. A span lies either within one paragraph or around whole paragraphs; the latter supports paragraph-level `onTap`.
4. Every scope is closed before `finish` (`UnclosedScope`), and a finished builder rejects further calls (`AlreadyFinished`).
5. With nested interactions, the innermost one wins.
6. Empty strings emit no `Text` op. A Swift `Text` with no style and no link emits no span.
7. Paragraph separators are not part of the IR.

Swift's closure-based builder already keeps begin/end paired. The engine rules catch custom nodes that misuse the builder.

## Styles across the boundary

Swift value types (`IR.TextStyle`, `IR.ParagraphStyle`, `IR.Span`, `IR.AttachmentDescriptor`, `IR.Gradient`) are what custom nodes pass to the builder. Each call converts them to C structs (`ATRTextStyle`, `ATRParagraphStyle`, `ATRAttachmentDescriptor`, `ATRGradientDescriptor`) that carry a **field mask**: a cleared bit means "inherit". C++ stores them as `std::optional` fields.

- Text style: font, **foreground fill** (a color or a gradient, `ATRFill`), background color, kern, baseline offset, **underline** (lines, pattern, optional thickness, corners), and **underline fill**. An underline whose fill is still unset after inheritance uses the foreground fill.
- Paragraph style: alignment, writing direction, line spacing, paragraph spacing.
- Alignment and writing direction use library enums with the same raw values in Swift, ObjC, and C++, because `NSTextAlignment` raw values differ between iOS and macOS. Underlines are engine-drawn decorations with library-defined lines and patterns, not `NSUnderlineStyle`.
- The IR records only what each scope sets; `atr::resolve` applies inheritance (see [layout-and-rendering.md](layout-and-rendering.md)).

## Resources and identifiers

- Fonts and colors are stored unresolved in ObjC++ tables and deduplicated with `isEqual:`. Dynamic colors can therefore be re-resolved per appearance. Color 0 is always the semantic label color, used as the root foreground.
- Gradients are deduplicated in C++ by value (colors, locations, points, scope).
- `InteractionID` is assigned by Swift (index into its closure table). `AttachmentID`, `FontRef`, `ColorRef`, and `GradientRef` are assigned by the engine. All are sequential within one document.

## Attachment descriptor

Fixed `width`/`height`, or adaptive `maxWidth`/`maxHeight` (at least one); an alignment kind plus offset; a `pipeline` (`Image` / `AsyncImage`, chosen from `ImageSource`); a `contentSize` known only for the Image pipeline; and an optional accessibility label.

## Dump format

`IR.Document.dump()` returns the engine's text form; snapshot tests compare it:

```
base paragraph{} text{fg=c0}
SPAN i0 text{}
  P paragraph{lineSpacing=4} text{font=f0 fg=c1}
    "Hello "
    SPAN text{font=f1 fg=g0 underline=single,solid}
      "World"
    END
    ATTACH a0 image size=fixed(16x12) content=40x20 align=center label="Local"
  /P
END
g0 = linear (0,0.5)->(1,0.5) [c1 c2] @[0 0.25] scope=paragraph
---
f0 = <fontName> <size>
c0 = <platform description>
```

- Text is quoted. `\` `"` `\n` `\r` `\t` are escaped, and other control characters print as `\u{X}`. Unpaired surrogates become U+FFFD.
- Numbers use the shortest round-trip form; integral values have no fraction.
- Fills print as `c<n>` (color) or `g<n>` (gradient), for example `fg=g0` or `underlineFill=c2`. Underlines print as `underline=<lines>,<pattern>[,<thickness>][,radius=<r>|,capsule]`, for example `underline=single,dash,2` or `underline=single,dot,capsule`.
- Everything before `---` is stable and can be asserted. Font and color descriptions come after it because platform descriptions vary across OS versions.
