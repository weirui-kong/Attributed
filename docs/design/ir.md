# IR

Status: implemented. The document lives in engine memory: storage, validation, and dump are C++ ([`Sources/AttributedEngine/`](../../Sources/AttributedEngine/)), resource deduplication is ObjC++ ([`Sources/AttributedEngineObjC/`](../../Sources/AttributedEngineObjC/)), and Swift ([`Sources/AttributedCore/IR/`](../../Sources/AttributedCore/IR/)) only forwards builder calls. Covered by [`Tests/AttributedCoreTests/`](../../Tests/AttributedCoreTests/) and [`Tests/AttributedEngineTests/`](../../Tests/AttributedEngineTests/).

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

Swift keeps only what must be Swift: interaction closures and attached values (of any type), a copy of each interaction's gesture, and image sources, which include the `defer` closures. `IR.LoweredText` pairs the engine document with those tables and exposes `interaction(for:)`, `gesture(for:)`, and `imageSource(for:)`.

## Engine storage (`atr::Document`)

```cpp
std::vector<Op> ops;               // Op { kind, first, second }
std::u16string text;               // all text, UTF-16
std::vector<TextStyle> textStyles;
std::vector<ParagraphStyle> paragraphStyles;
std::vector<Gradient> gradients;   // deduplicated
std::vector<Gesture> interactions; // index = InteractionID
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
4. A span's interaction must have been registered (`UnknownInteraction`).
5. Every scope is closed before `finish` (`UnclosedScope`), and a finished builder rejects further calls (`AlreadyFinished`).
6. With nested interactions, the innermost one per gesture key wins (see [dsl.md](dsl.md)).
7. Empty strings emit no `Text` op. A Swift `Text` with no style and no link emits no span.
8. Paragraph separators are not part of the IR.

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
- `IR.Builder.register(_:gesture:)` registers an interaction with its gesture in the engine, which assigns the `InteractionID`; Swift stores the closure or value at the same index and checks that the indices agree. `AttachmentID`, `FontRef`, `ColorRef`, and `GradientRef` are also assigned by the engine. All are sequential within one document.

## Attachment descriptor

A `kind`: `Image` (the default) or `Spacer`.

- Images: fixed `width`/`height`, or adaptive `maxWidth`/`maxHeight` (at least one); an alignment kind plus offset; a `pipeline` (`Image` / `AsyncImage`, chosen from `ImageSource`); a `contentSize` known only for the Image pipeline; and an optional accessibility label.
- Spacers: `width`, and either `height` or the `InferredHeight` field, which takes the adjacent text's height. They draw nothing and have no image source on the Swift side.

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
i0 = tap(1)
---
f0 = <fontName> <size>
c0 = <platform description>
```

- Text is quoted. `\` `"` `\n` `\r` `\t` are escaped, and other control characters print as `\u{X}`. Unpaired surrogates become U+FFFD.
- Numbers use the shortest round-trip form; integral values have no fraction.
- Spacers print as `ATTACH a<n> spacer width=<w> height=<h|inferred>`.
- Interactions print after gradients as `i<n> = tap(<count>)` or `i<n> = longPress(<seconds>)`.
- Fills print as `c<n>` (color) or `g<n>` (gradient), for example `fg=g0` or `underlineFill=c2`. Underlines print as `underline=<lines>,<pattern>[,<thickness>][,radius=<r>|,capsule]`, for example `underline=single,dash,2` or `underline=single,dot,capsule`.
- Everything before `---` is stable and can be asserted. Font and color descriptions come after it because platform descriptions vary across OS versions.
