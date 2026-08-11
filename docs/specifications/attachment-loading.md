# Attachment Loading Specification

## Initial state

- A local image starts as `.resolved`.
- An async image starts as `.loading`.
- A remote image first performs `cachedImage(for:)` synchronously.
- A valid cached remote image starts as `.resolved` and must not start `image(for:)`.
- Cache miss, cache error, or a zero-sized cached image starts as `.loading` and falls back to `image(for:)`.
- A missing remote provider is a programmer error and must fail a precondition.

## Initial content

- An explicit placeholder is installed as the attachment image while loading.
- Without a placeholder, the attachment has no image while loading. Intrinsic and adaptive policies initially produce zero size; fixed policy retains its configured bounds.
- Cached content takes precedence over a placeholder.

## Resolution

Loaded images must have positive width and height. An invalid image changes the attachment to `.failed` with `URLError.cannotDecodeContentData`.

On success:

1. Capture the old attachment size.
2. Install the image on the same attachment, replacing an explicit placeholder when present.
3. Recalculate bounds.
4. Set state to `.resolved`.
5. Emit `attachmentContentChanged` when size is unchanged, otherwise emit `attachmentLayoutChanged`.
6. Emit `attachmentStateChanged`.

On failure, keep an explicit placeholder when present, otherwise remain empty, set `.failed(error)`, and emit a state change.

On cancellation, cancel tracked loading tasks, keep the current attachment image, set still-loading attachments to `.cancelled`, and emit a state change. Cancellation does not replace an existing placeholder.

## Sizing

- Fixed size is independent of the loaded image dimensions.
- Intrinsic size follows the current image size.
- Adaptive size preserves aspect ratio, observes configured maxima and available line width, and does not upscale.
- A change from loading bounds to final bounds requires layout invalidation.

## Provider rules

`cachedImage(for:)` is synchronous and may return `nil` for ordinary misses. `image(for:)` is asynchronous and must return a decoded platform image or throw. Core treats a cache error as a reason to attempt asynchronous loading rather than as a terminal attachment failure.

The corresponding implementation and executable assertions are in [`Sources/Core/Image.swift`](../../Sources/Core/Image.swift), [`Sources/Core/AttributedText.swift`](../../Sources/Core/AttributedText.swift), and [`Tests/CoreTests/CoreTests.swift`](../../Tests/CoreTests/CoreTests.swift).
