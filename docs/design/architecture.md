# Architecture

## Layers

```
Swift DSL (value-type nodes + result builders)          implemented
  └─ lower(into:) ──► IR.Builder (thin) ──► ATRDocumentBuilder (ObjC++) ──► atr::DocumentBuilder (C++)
                        implemented: op stream, text pool, resources, validation, dump
IR.LoweredText = ATRDocument + Swift-only tables (interaction closures, image sources)
ATRDocument ──► C++ engine                               implemented
                                          ├ style inheritance, run table, paragraphs
                                          ├ CoreText layout (CTTypesetter / CTLine) ──► ATRTextLayout
                                          └ gradient joining per scope (line / paragraph / document)
                                          ├ CGContext rendering (Render.cpp) ──► ATRRenderSnapshot
                                          └ hit regions ──► ATRHitView + gesture registry/policy
Attributed.TextView (Swift, public) ⊃ ATRTextDisplayView (ObjC, internal):
    layout per width (or a prepared layout, applied synchronously), layer
    bitmaps, viewport tiles, viewport hit views; events go back to Swift as
    interaction IDs and become InteractionEvents
```

Engine rules:

- Text is indexed in UTF-16, matching CoreText. Implemented.
- Fonts and colors reach the engine as resource indices. An appearance change re-resolves the color table and redraws without relayout. Implemented. A Dynamic Type change re-resolving the font table and relaying out is planned.
- Layout results are immutable snapshots computed for a width, safe to compute off the main thread; views apply them synchronously. Implemented. See [layout-and-rendering.md](layout-and-rendering.md).

## SwiftPM targets

Tools version 6.0 with the Swift 6 language mode. Each target lives in `Sources/<target>` and its tests in `Tests/<target>Tests`, so `Package.swift` needs no custom paths.

```
Attributed (facade)
├─ AttributedUI ──────── AttributedViewObjC ─┐
└─ AttributedCore ────── AttributedEngineObjC ┴─ AttributedEngine (C++)
```

| Target | Language | Product | Contents |
| --- | --- | --- | --- |
| `Attributed` | Swift | yes | Re-exports `AttributedCore` and `AttributedUI`; `ATR*` aliases |
| `AttributedCore` | Swift | yes | `DSL/` (nodes, modifiers, gestures, gradients, styles), `IR/` (thin builder over the engine), `Layout/` (`TextContainer`, `TextLayout`, `PreparedText`). No views, so it can measure and prepare off the main thread. |
| `AttributedUI` | Swift | yes | `TextView`, `TextViewDelegate`, `InteractionEvent`, `TextTransition`; closures, values, and AsyncImage loading |
| `AttributedEngineObjC` | ObjC++ | no | Model facade: `ATRDocumentBuilder`, `ATRDocument`, `ATRTextLayout`, `ATRRenderSnapshot`, `ATRGlyphSnapshot`, C value types |
| `AttributedViewObjC` | ObjC++ | no | View layer: `ATRTextDisplayView`, `ATRHitView`, gesture bindings, factories, registry, policy, text transition effects (`ATRNumericTextTransition`, Metal); private `ATRTileController`, `ATRScrollObserver`, `ATRHitViewManager`. Uses only the model facade's public ObjC API. |
| `AttributedEngine` | C++20 | no | `document/`, `resolve/`, `layout/`, `render/` with matching headers under `include/atr/`; links CoreFoundation, CoreGraphics, CoreText |

| Test target | Covers |
| --- | --- |
| `AttributedCoreTests` | Lowering snapshots, Swift layout API |
| `AttributedUITests` | `TextView` delegate events, AsyncImage loading, prepared text from a background queue |
| `AttributedEngineTests` | Builder validation, dump, resolution, layout, shared fallback fonts, incremental relayout, rendering pixels, glyph atoms |
| `AttributedViewObjCTests` | Hit views, gestures, viewport hit view reuse, tiling, scroll observation, prepared layouts, async rendering, text transitions |

- A SwiftPM target can't mix Swift with C-family code, and the view and model layers are split on purpose, so there are three non-Swift targets.
- Cross-target internals:
  - Swift targets share internals through `package` access. For example, `AttributedUI` reads the lowered document's engine object and handler tables.
  - Swift imports the ObjC facades with `internal import` or `package import`, so no ObjC type reaches clients.
- The facades' public headers are pure Objective-C (no C++), so Swift needs no C++ interop.
- ObjC++ does not autolink platform frameworks, so each ObjC target declares its frameworks in `linkerSettings`.

## Language boundary

- The engine is C++ behind an ObjC++ facade. Swift does not use C++ interop directly: interop is contagious to clients and works poorly with library evolution and XCFramework distribution.
- The IR crosses the boundary in one call, never node by node or character by character.

## Verification

- macOS: `swift test`
- iOS: `xcodebuild -scheme Attributed-Package -destination "id=<iPhone simulator UDID>" test` runs all four test targets. `xcodebuild` may keep running after the last bundle reports, so scripts should stop it once every `Test Suite 'All tests'` line has appeared.
- Building needs the Metal Toolchain (`xcodebuild -downloadComponent MetalToolchain`): `AttributedViewObjC` compiles `ATRNumericText.metal` into its resource bundle (decision 50).
- After adding a header to a target's `include/`, clear the explicit module cache (decision 49).
- Demo: `Demo/AttributedDemo` (UIKit). Launch arguments `-benchmark size,script,style,mode` (segment indexes) and `-stressSeconds N` open the Performance and Stress pages for repeatable measurements.
- README animation: launching the Demo with `-readmeTransition` (or `-readmeTransition dark`) shows only the looping card and logs its frame as `README_TRANSITION_CARD`. Record one cycle with `xcrun simctl io <udid> recordVideo`, then crop it to the card with ffmpeg. One cycle is four transitions, 6.4 s, starting just before a transition. Make a 30 fps GIF at 2x. Snap near-white and near-black to pure white and black first, so the card has no visible edge on GitHub. Write it to `docs/images/readme/transition-{light,dark}.gif`.
- README images: launching the Demo with `-readmeShots` renders every README example in light and dark to the app's `Documents/readme`; copy them to [`docs/images/readme/`](../images/readme/). The example texts live in `ReadmeShotsViewController.swift` and must stay in sync with the README's code blocks.
