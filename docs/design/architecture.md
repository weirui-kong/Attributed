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

Tools version 6.0 with the Swift 6 language mode.

| Target | Path | Status | Contents |
| --- | --- | --- | --- |
| `Attributed` (only product) | `Sources/Attributed` | implemented | `@_exported import AttributedCore` and `ATR*` aliases |
| `AttributedCore` | `Sources/Core` | implemented | `Attributed` namespace, DSL, thin `IR.Builder`, `TextView` wrapper |
| `AttributedEngineObjC` | `Sources/EngineObjC` | implemented | ObjC++ facade with `ATR` prefix: document builder, layout, render snapshot, display view, hit views, gestures; pure-ObjC public headers in `include/` |
| `AttributedEngine` | `Sources/Engine` | implemented (document, resolution, layout) | C++20 engine on CoreText; headers in `include/atr/`; links CoreFoundation, CoreGraphics, CoreText |
| `AttributedCoreTests` | `Tests/CoreTests` | implemented | Swift lowering snapshot tests |
| `AttributedEngineTests` | `Tests/EngineTests` | implemented | ObjC++ tests for validation, dump, dedup, resolution, layout |

A SwiftPM target can't mix Swift with C-family code, so Swift, the ObjC++ facade, and the C++ engine are separate targets. Swift imports the facade with `internal import` so no ObjC type leaks into the public API. The facade's public headers are pure Objective-C (no C++), so Swift needs no C++ interop. ObjC++ does not autolink platform frameworks, so the facade declares Foundation, QuartzCore, UIKit (iOS), and AppKit (macOS) in `linkerSettings`. The Swift test target depends on the facade directly to inspect hit views.

## Language boundary

- The engine is C++ behind an ObjC++ facade. Swift does not use C++ interop directly: interop is contagious to clients and works poorly with library evolution and XCFramework distribution.
- The IR crosses the boundary in one call, never node by node or character by character.

## Verification

- macOS: `swift test`
- iOS: `xcodebuild -scheme Attributed -destination "id=<iPhone simulator UDID>" test` (runs both test targets)
