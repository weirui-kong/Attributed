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
    layout per width, layer bitmaps, viewport tiles, hit views; events go
    back to Swift as interaction IDs and become InteractionEvents
```

Planned engine rules:

- Text is indexed in UTF-16, matching CoreText.
- Fonts and colors reach the engine as resource indices. An appearance change re-resolves the color table and redraws without relayout. A Dynamic Type change re-resolves the font table and relays out.
- Layout results are immutable snapshots computed for a width, safe to compute off the main thread. See [layout-and-rendering.md](layout-and-rendering.md).

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
| `AttributedCore` | Swift | yes | `DSL/` (nodes, modifiers, gestures, gradients, styles), `IR/` (thin builder over the engine), `Layout/` (`TextContainer`, `TextLayout`). No views, so it can measure off the main thread. |
| `AttributedUI` | Swift | yes | `TextView`, `TextViewDelegate`, `InteractionEvent`; closures, values, and AsyncImage loading |
| `AttributedEngineObjC` | ObjC++ | no | Model facade: `ATRDocumentBuilder`, `ATRDocument`, `ATRTextLayout`, `ATRRenderSnapshot`, C value types |
| `AttributedViewObjC` | ObjC++ | no | View layer: `ATRTextDisplayView`, `ATRHitView`, gesture bindings, factories, registry, policy. Uses only the model facade's public ObjC API. |
| `AttributedEngine` | C++20 | no | `document/`, `resolve/`, `layout/`, `render/` with matching headers under `include/atr/`; links CoreFoundation, CoreGraphics, CoreText |

| Test target | Covers |
| --- | --- |
| `AttributedCoreTests` | Lowering snapshots, Swift layout API |
| `AttributedUITests` | `TextView` delegate events and AsyncImage loading |
| `AttributedEngineTests` | Builder validation, dump, resolution, layout, rendering pixels |
| `AttributedViewObjCTests` | Hit views, gestures, tiling, async rendering |

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
- iOS: `xcodebuild -scheme Attributed -destination "id=<iPhone simulator UDID>" test` (runs both test targets)
