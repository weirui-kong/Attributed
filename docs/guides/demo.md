# Using the Demo

The cross-platform Demo project is [`Demo/AttributedDemo/AttributedDemo.xcodeproj`](../../Demo/AttributedDemo/AttributedDemo.xcodeproj). Its deployment targets match the package: iOS 16 and macOS 13.

<p align="center">
  <img src="../assets/feature-showcase.png" alt="Attributed All Features showcase running on iPad" height="400">
</p>

The home screen is a navigation list. Current pages cover:

- A single deliberately dense All Features showcase
- Long text and live width changes
- Mixed inline styles
- Result-builder conditionals and loops
- Paragraph alignment and spacing
- LTR, RTL, and mixed-direction text
- URL links
- Local image overview
- Intrinsic, fixed, and adaptive image sizing
- Attachment baseline, center, top, bottom, and offset alignment
- Long text wrapping around inline images
- Async success, failure, empty loading, and placeholder states
- Remote images with and without placeholders
- Multiple concurrent remote images

The page index is defined in [`ContentView.swift`](../../Demo/AttributedDemo/AttributedDemo/ContentView.swift). Typography examples are in [`TypographyDemoViews.swift`](../../Demo/AttributedDemo/AttributedDemo/TypographyDemoViews.swift), direction examples in [`DirectionDemoView.swift`](../../Demo/AttributedDemo/AttributedDemo/DirectionDemoView.swift), and image examples in [`ImageDemoViews.swift`](../../Demo/AttributedDemo/AttributedDemo/ImageDemoViews.swift).

The combined showcase is implemented in [`FeatureShowcaseDemoView.swift`](../../Demo/AttributedDemo/AttributedDemo/FeatureShowcaseDemoView.swift). It intentionally labels custom closure interaction as registration-only because host-side invocation is not implemented yet.

The Demo injects `ImageDownloader(enableDiskCache: false, enableMemoryCache: false)` at launch. This makes the package-managed loading path visible when revisiting remote-image pages, subject to any caching performed by `URLSession` itself.
