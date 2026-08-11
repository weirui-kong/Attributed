# Working with Images

## Local image

```swift
AParagraph {
    "Online "
    AImage(statusImage, accessibilityLabel: "Online")
        .size(.fixed(width: 18, height: 18))
        .alignment(.center)
}
```

Use `.intrinsic` when the platform image already has the desired point size. Use `.fixed` for exact inline bounds and `.adaptive` for larger content that should preserve aspect ratio and respond to available width.

## Async image

```swift
AImage(
    source: .async {
        try await imageService.load()
    },
    accessibilityLabel: "Profile photo"
)
.size(.adaptive(maxWidth: 320, maxHeight: 240))
```

Without a placeholder, the attachment remains empty while loading. Supply `placeholder:` when content should be visible before resolution.

## Remote image

Install one provider before building documents containing remote images:

```swift
import Attributed
import AttributedUtility

ARemoteImageEnvironment.provider = ImageDownloader()
```

Then use the URL source:

```swift
AImage(
    remoteURL: imageURL,
    accessibilityLabel: "Article cover"
)
.size(.adaptive(maxWidth: 640, maxHeight: 320))
```

For deterministic loading-state tests, disable the downloader-managed caches:

```swift
ARemoteImageEnvironment.provider = ImageDownloader(
    enableDiskCache: false,
    enableMemoryCache: false
)
```

This does not disable caching performed by the supplied `URLSession` itself. Use a session configuration with the desired request and `URLCache` policy when that distinction matters.

## Observe state

```swift
let rendered = document.render()

Task { @MainActor in
    for await update in rendered.updates() {
        handle(update)
    }
}
```

The built-in TextKit and SwiftUI hosts already observe this stream. Subscribe directly only when application UI or diagnostics also need attachment events. Call `rendered.cancel()` on the main actor to cancel attachments that are still loading.
