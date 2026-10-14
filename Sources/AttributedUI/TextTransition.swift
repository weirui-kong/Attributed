// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import AttributedCore
internal import AttributedViewObjC

public extension Attributed {
// How a text view gets from the text on screen to new text; pass one to
// `TextView.setText(_:transition:completion:)`.
struct TextTransition {
    // Returns the effect to run: the running one when it is of this kind and
    // can carry on, otherwise a new one.
    let resolve: (ATRTextTransitionEffect?) -> ATRTextTransitionEffect

    // SwiftUI's `.contentTransition(.numericText())`, for short texts such as
    // prices and counters. iOS only; on macOS the text is simply replaced.
    public static func numericText(
        _ direction: NumericTextDirection = .downward,
        anchoring: NumericTextAnchoring = .screen
    ) -> TextTransition {
        TextTransition { running in
            let effect = running as? ATRNumericTextTransition ?? ATRNumericTextTransition()
            effect.direction = direction.engineValue
            effect.anchoring = anchoring.engineValue
            return effect
        }
    }

    // Builds what numericText otherwise builds on its first run, on the main
    // thread. Synchronous and safe on any thread; meant for a background one.
    public static func prewarmNumericText() -> TextTransitionPrewarmResult {
        TextTransitionPrewarmResult(ATRNumericTextTransition.prewarm())
    }
}

// Which way glyphs travel. `.downward` is what SwiftUI shows for
// `numericText(countsDown: false)` and for a decreasing `numericText(value:)`.
enum NumericTextDirection: Hashable, Sendable {
    // New glyphs come in from above, old ones leave downward.
    case downward
    // New glyphs come in from below, old ones leave upward.
    case upward
}

// What glyphs already on screen hold on to when the view moves while its
// text changes.
enum NumericTextAnchoring: Hashable, Sendable {
    // Their place on screen: a kept glyph slides from where it was to where it
    // belongs now. For a view that resizes or re-aligns because of its text.
    case screen
    // The view: glyphs move with it at once and only travel inside it. For a
    // view moved for reasons of its own while its text changes.
    case view
}

// How a `setText(_:transition:completion:)` call ended.
enum TextTransitionOutcome: Hashable, Sendable {
    // The transition ran to its end with this call's text on screen.
    case finished
    // A later `setText(_:transition:)` took over first.
    case superseded
    // Cut short with the text shown at once: a plain `text` assignment,
    // leaving the window, or a change the effect could not follow.
    case interrupted
    // No transition ran and the text was simply replaced.
    case skipped
}

enum TextTransitionPrewarmResult: Hashable, Sendable {
    // Built by this call and kept.
    case succeeded
    // Built by this call; the transition is not available on this device.
    case failed
    // Built earlier, by a prewarm or by a first use.
    case alreadyPrewarmed
    // An earlier build found the transition unavailable; it is not retried.
    case alreadyFailed
    // Another thread is building it; this call left it alone.
    case alreadyInProgress
    // Built by this call, but a first use elsewhere stored its result first.
    case superseded
}
}

extension Attributed.NumericTextDirection {
    var engineValue: ATRNumericTextDirection {
        switch self {
        case .downward:
            .downward
        case .upward:
            .upward
        }
    }
}

extension Attributed.NumericTextAnchoring {
    var engineValue: ATRNumericTextAnchoring {
        switch self {
        case .screen:
            .screen
        case .view:
            .view
        }
    }
}

extension Attributed.TextTransitionOutcome {
    init(_ outcome: ATRTextTransitionOutcome) {
        switch outcome {
        case .finished:
            self = .finished
        case .superseded:
            self = .superseded
        case .interrupted:
            self = .interrupted
        case .skipped:
            self = .skipped
        @unknown default:
            self = .skipped
        }
    }
}

extension Attributed.TextTransitionPrewarmResult {
    init(_ result: ATRTextTransitionPrewarmResult) {
        switch result {
        case .succeeded:
            self = .succeeded
        case .failed:
            self = .failed
        case .alreadyPrewarmed:
            self = .alreadyPrewarmed
        case .alreadyFailed:
            self = .alreadyFailed
        case .alreadyInProgress:
            self = .alreadyInProgress
        case .superseded:
            self = .superseded
        @unknown default:
            self = .failed
        }
    }
}
