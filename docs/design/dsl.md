# DSL

Status: lowering to the IR is implemented in [`Sources/AttributedCore/`](../../Sources/AttributedCore/). Rendering, loading, and tap dispatch wait for the engine and the view.

## Document and extension point

```swift
let text = ATRAttributedText {
    ATRParagraph { "Hello "; ATRText("World").font(.boldSystemFont(ofSize: 16)) }
        .font(.systemFont(ofSize: 12))
        .lineSpacing(4)
}
let lowered = text.lower()   // IR.LoweredText
```

- Every node implements `lower(into builder: inout IR.Builder)`. Block nodes (`AttributedBlock`) appear in documents; inline nodes (`AttributedInline`) appear in paragraphs. Bare strings in a paragraph become `Text`.
- Custom nodes use the same public `IR.Builder` as the built-in nodes: `paragraph`, `span`, `text`, `image`, `font`, `color`, `gradient`, `register`.
- DSL modifiers return modified copies.

## Text

`Text` modifiers: `font`, `foregroundColor`, `gradient(_:)`, `backgroundColor`, `kern`, `baselineOffset`, `underline(_:color:)`, `underline(_:gradient:)`, `link(_:)`.

`Paragraph` modifiers: `font`, `foregroundColor`, `backgroundColor`, `kern`, `alignment`, `baseWritingDirection`, `lineSpacing`, `paragraphSpacing`.

### Foreground fill

The foreground is one fill: a color or a gradient. `foregroundColor` and `gradient` replace each other, and the last one set wins, both on one node and when a child overrides its parent.

### Underlines

```swift
Text("a").underline()                                        // single, solid, follows the foreground
Text("b").underline(.double, color: .blue)
Text("c").underline(ATRUnderlineStyle(pattern: .dash, thickness: 2), gradient: sunset)
Text("d").underline(ATRUnderlineStyle(thickness: 4, corners: .capsule))
```

- The engine draws underlines as decorations; the platform underline is not used. This is what allows gradient underlines.
- `UnderlineStyle(lines:pattern:thickness:)`:
  - `lines`: `.single` or `.double`.
  - `pattern`: `.solid`, `.dot`, `.dash`, `.dashDot`, or `.dashDotDot`.
  - `thickness`: nil uses the font's underline thickness.
  - `corners`: `.square` (default), `.radius(r)` clamped to half the drawn thickness, or `.capsule` (half the drawn thickness, so it also works with font-metric thickness). Corners apply to both ends of every drawn segment, including each dash and dot.
  - Shorthands: `.single`, `.double`.
- Adjacent runs on one line with an equal underline and fill are merged into one segment before corners are applied, so run boundaries never show rounded caps.
- An underline without its own color or gradient uses the text's foreground fill, including a foreground gradient.
- An underline gradient joins with equal text gradients in the same scope, so a gradient underline lines up with the gradient text above it.

## Group

```swift
ATRParagraph {
    "Before "
    ATRGroup {
        ATRText("several ").font(bold)
        ATRText("nodes")
    }
    .onTap(value: "group")      // one interaction for both nodes
}
```

`Group` (alias `ATRGroup`) combines nodes without adding anything of its own, like SwiftUI's `Group`. It emits no ops itself. Inside a paragraph it groups inline nodes; at the top level it groups blocks. The builder decides which from context. A modifier applied to a Group, such as `onTap`, covers all its children as one unit: one interaction, one range, and hit regions merged per line.

## Interactions

```swift
Text("site").link(url)                                  // a single tap carrying the URL
Text("item").onTap(count: 2, value: item)               // any value, any tap count
Paragraph { ... }.onLongPress(minimumDuration: 1) { … } // closure action
```

- Gestures: `.tap(count:)` (default 1) and `.longPress(minimumDuration:)` (default 0.5 s).
- `onTap` and `onLongPress` work on any node, including `Text`, `Image`, `Paragraph`, and custom nodes. Each comes in two forms:
  - with a closure;
  - with `value:` of any type.
  - The value forms are `@_disfavoredOverload`, so a trailing closure always selects the closure form instead of becoming the value.
- `Interaction` is `.action(closure)` or `.value(Any)`. `.link(url)` is just `.value(url)` with a single tap.
- They wrap the node in `Attributed.Interactive` (alias `ATRInteractive`), which lowers to a span carrying an interaction ID. The engine assigns the ID and stores the gesture; the Swift handler is stored at the same index.
- Nesting: a run collects the interactions of every enclosing span, keeping the innermost one per gesture key. A tap's key includes its count, and long presses share one key. So a single tap nested in a double tap keeps both, and a tap nested in a tap keeps only the inner one.
- Modifier order matters: these modifiers return a wrapper, so `Text("x").font(f).onTap {}` compiles but `.onTap {}.font(f)` does not.

### Delegate events

Every recognized interaction reaches `TextViewDelegate.textView(_:didRecognize:)` as an `InteractionEvent`:

| Field | Meaning |
| --- | --- |
| `gesture` | The recognized gesture |
| `value` / `value(as:)` | The attached value, nil for closure interactions |
| `range` | UTF-16 `NSRange` of the node in the document text. Paragraphs are joined by one `\n` and each attachment is one U+FFFC, as in an `NSAttributedString` of the same text. |
| `text` | The document text in `range` |
| `location` | Where the gesture was recognized, in text-view coordinates |
| `rects` | Every hit rect of the interaction, in text-view coordinates |

- A closure interaction runs its closure first, and then the delegate is called.
- When the value is a `URL`, the view asks `textView(_:shouldOpen:event:)` (default `true`) and opens the URL with the system.

## Images

```swift
Image(.resolved(image), size: .fixed(width: 16, height: 12), accessibilityLabel: "Logo")
Image(.defer { makeImage() }, size: .adaptive(maxWidth: 200))
    .alignment(.center)
```

- `ImageSource` selects the pipeline:
  - `.resolved(PlatformImage)` uses the Image pipeline; its content is available at lowering time.
  - `` .`defer`(@MainActor () -> PlatformImage) `` uses the AsyncImage pipeline. The host calls the closure after the initial render and updates rendering once the image is installed (planned).
- A size is required: `.fixed(width:height:)` or `.adaptive(maxWidth:maxHeight:)`. Adaptive preserves the aspect ratio, fits the maxima and the available line width, never upscales, and needs at least one maximum. There is no intrinsic size.
- An adaptive AsyncImage with no size yet lays out as a zero-width placeholder as tall as the adjacent character: the text right before it, else the text right after it, else the default font. The placeholder sits on the baseline like that character, so the line keeps its height until the image arrives.
- Update rule: a fixed AsyncImage only redraws when its content arrives. An adaptive one needs a relayout, using the loaded size as a content-size override.
- Alignment: `.baseline`, `.center`, `.top`, `.bottom`, `.offset(_:)`.
- Remote URLs, async loaders, and placeholders from v0.1 were removed.

## Gradients

```swift
let sunset = ATRTextGradient(colors: [.red, .orange])   // left → right, .paragraph scope by default
ATRParagraph {
    ATRText("Warm").gradient(sunset)
    " plain "
    ATRText("glow").gradient(sunset)   // joined with "Warm" into one continuous gradient
}
```

- `TextGradient(colors:locations:startPoint:endPoint:scope:)`:
  - At least two colors.
  - `locations`, when given, has one value per color, ascending within 0...1; without it, colors are spaced evenly.
  - Start and end points are `GradientPoint` unit coordinates in the joined gradient rect.
- A gradient fills glyphs in place of the foreground color. It is currently a `Text` modifier only.
- `GradientScope` is not a rendering mode. It is the **lookup space** for joining gradients. Within one scope, runs whose gradients are equal (scope included) are drawn as one continuous gradient, laid out over the union of their typographic bounds (advance width × line ascent/descent). The runs need not be adjacent.

| Scope | Lookup space |
| --- | --- |
| `.line` | one CTLine |
| `.paragraph` (default) | one paragraph, across its lines |
| `.document` | the whole document. **Warning:** every matching run must be laid out before any can be drawn, which defeats incremental and tiled rendering and is very expensive for long text. |

- Emoji are excluded from gradients by default and keep their own colors. The hosting text view will offer a switch to include them (planned).
