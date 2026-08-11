# Remote Images

## Provider contract

Remote images require an `ARemoteImageProvider` installed before the document is rendered:

```swift
ARemoteImageEnvironment.provider = provider
```

If a remote image is rendered without a provider, the package intentionally stops with a precondition failure. The contract is defined in [`Sources/Core/RemoteImageProvider.swift`](../../Sources/Core/RemoteImageProvider.swift).

A provider has two operations:

```swift
func cachedImage(for url: URL) throws -> PlatformImage?
func image(for url: URL) async throws -> PlatformImage
```

`cachedImage(for:)` must return immediately. A normal cache miss is `nil`; throwing is reserved for exceptional cache or input failures. The protocol supplies a default implementation that returns `nil`.

Rendering checks the synchronous cache first. A valid cached image is rendered immediately and no asynchronous request is started. A miss, thrown cache error, or zero-sized cached image falls back to `image(for:)`.

## Built-in downloader

`AttributedUtility.ImageDownloader` is a small URLSession-based provider:

```swift
let downloader = ImageDownloader(
    enableDiskCache: true,
    enableMemoryCache: true
)
```

Both caches are enabled by default and can be controlled independently.

- Memory cache keys are `URL` values and access is protected by a lock.
- Disk files are stored under `FileManager.temporaryDirectory/AttributedImageDownloader` unless a custom directory is provided.
- Disk filenames are SHA-256 hashes of `url.absoluteString`.
- Only HTTP responses with status codes from 200 through 299 are accepted.
- Undecodable response data throws `URLError.cannotDecodeContentData`.
- Missing cache files return `nil`; unreadable or undecodable existing cache files throw.
- Cache directory creation and disk writes are best effort. A write failure does not fail an otherwise successful download.
- A cache-read error encountered by the asynchronous method falls through to a network request.

The downloader does not provide request coalescing, cache expiry, explicit eviction, or an independent HTTP cache policy. Disabling both internal caches disables only `ImageDownloader`'s caches; the configured `URLSession` may still apply its own `URLCache` policy.

The Demo installs one process-wide downloader with both internal caches disabled in [`Demo/AttributedDemo/AttributedDemo/AttributedDemoApp.swift`](../../Demo/AttributedDemo/AttributedDemo/AttributedDemoApp.swift).
