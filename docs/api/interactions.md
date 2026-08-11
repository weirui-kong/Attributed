# Links and Interactions

`ALink` supports a URL or a closure:

```swift
ALink("Website", url: websiteURL)

ALink("Retry") {
    retry()
}
```

Every link receives an internal interaction ID stored under `NSAttributedString.Key.attributedInteractionID`. URL links additionally receive the standard `.link` attribute, so TextKit can recognize them as URL links. Closure links are registered in the rendered text's interaction registry and can be recovered with `interaction(for:)` when the ID is known.

The current TextKit hosts do not yet expose a delegate or callback that invokes registered closure actions. Custom-action registration is implemented in Core, but end-to-end custom-action handling remains future host work. URL behavior is left to the underlying text system.

The implementation is in [`Sources/Core/Link.swift`](../../Sources/Core/Link.swift) and [`Sources/Core/Interaction.swift`](../../Sources/Core/Interaction.swift).
