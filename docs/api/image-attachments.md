# Image Attachments

`AImage` is an inline node backed by `NSTextAttachment`. It can appear anywhere another inline node is accepted.

## Sources

```swift
AImage(platformImage)

AImage(source: .async {
    try await loadImage()
})

AImage(remoteURL: imageURL)
```

The three source forms are:

- `.image(PlatformImage)`: available synchronously and immediately resolved.
- `.async(@Sendable () async throws -> PlatformImage)`: loaded after rendering.
- `.remote(URL)`: resolved through the global remote image provider.

`PlatformImage` is `UIImage` on UIKit and `NSImage` on AppKit. The public declarations are in [`Sources/Core/Image.swift`](../../Sources/Core/Image.swift) and [`Sources/Core/Platform.swift`](../../Sources/Core/Platform.swift).

## Size policies

- `.intrinsic` uses the image's native point size.
- `.fixed(width:height:)` always uses the supplied positive finite size and may change the image's aspect ratio.
- `.adaptive(maxWidth:maxHeight:)` preserves aspect ratio, honors the supplied limits and available line width, and never upscales beyond the image's native size. At least one maximum must be supplied.

Invalid fixed or adaptive values fail a precondition during rendering.

## Alignment policies

- `.baseline`
- `.center`
- `.top`
- `.bottom`
- `.offset(CGFloat)`

Alignment is calculated against the surrounding font metrics. If no font is present, the platform body/system font is used.

## Placeholder and loading state

An async or remote image may supply a `placeholder`. A placeholder is displayed using the selected size policy until loading finishes. If no placeholder is supplied, the attachment has no image while loading.

Intrinsic and adaptive attachments without a placeholder initially occupy zero size. A fixed attachment retains its configured bounds but draws no image. When loading succeeds, the same attachment installs the resolved image and triggers content or layout invalidation as required.

On failure or cancellation, an explicit placeholder remains installed. Without a placeholder, the attachment remains empty and exposes the terminal state through `ARenderedAttachment`. A synchronously cached remote image bypasses the loading state.

The package does not yet expose a public custom-view attachment API.

## Accessibility

`accessibilityLabel` is normalized so an empty string becomes `nil` and is exposed through `ARenderedAttachment`.

## Runtime state

An attachment can be `.loading`, `.resolved`, `.failed(Error)`, or `.cancelled`. `ARenderedAttributedText.attachments` returns attachments ordered by their range, and `attachment(for:)` performs lookup by ID. Both APIs are main-actor isolated.

Successful loading emits either `attachmentContentChanged` or `attachmentLayoutChanged`, followed by `attachmentStateChanged`. Failure and cancellation emit a state change. `cancel()` cancels attachments that are still loading. See [`Sources/Core/AttributedText.swift`](../../Sources/Core/AttributedText.swift).
