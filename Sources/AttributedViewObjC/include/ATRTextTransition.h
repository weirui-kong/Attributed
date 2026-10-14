// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#import "ATRGlyphSnapshot.h"
#import "ATRTypes.h"

// How a transition to new text ended.
typedef NS_ENUM(uint8_t, ATRTextTransitionOutcome) {
    // Ran to its end with that text on screen.
    ATRTextTransitionOutcomeFinished,
    // A later transition took over before this one finished.
    ATRTextTransitionOutcomeSuperseded,
    // Cut short with the text shown at once: a plain assignment, leaving the
    // window, or a change the effect could not follow.
    ATRTextTransitionOutcomeInterrupted,
    // No transition ran; the text was simply replaced.
    ATRTextTransitionOutcomeSkipped,
};

// What one prewarm call did.
typedef NS_ENUM(uint8_t, ATRTextTransitionPrewarmResult) {
    // Built by this call and kept.
    ATRTextTransitionPrewarmResultSucceeded,
    // Built by this call; the transition is not available on this device.
    ATRTextTransitionPrewarmResultFailed,
    // Built earlier, by a prewarm or by a first use.
    ATRTextTransitionPrewarmResultAlreadyPrewarmed,
    // An earlier build found the transition unavailable; it is not retried.
    ATRTextTransitionPrewarmResultAlreadyFailed,
    // Another thread is building it; this call left it alone.
    ATRTextTransitionPrewarmResultAlreadyInProgress,
    // Built by this call, but a first use elsewhere stored its result first.
    ATRTextTransitionPrewarmResultSuperseded,
};

// One run of an effect getting from the content on screen to new content.
// The effect takes over showing the content in `begin` and gives it back by
// calling the completion, after which the host calls `cancel`.
@protocol ATRTextTransitionEffect <NSObject>

// Starts showing `snapshot`, the content on screen now, over `host`, whose
// own drawing the host then hides. NO when the effect cannot run here.
- (BOOL)beginOnHost:(nonnull ATRPlatformView *)host
           snapshot:(nonnull ATRGlyphSnapshot *)snapshot
         completion:(nonnull void (^)(void))completion;
// New content is laid out. Called once after `begin`, and again for every
// further change while the effect runs.
- (void)transitionToSnapshot:(nonnull ATRGlyphSnapshot *)snapshot;
// The content being shown was laid out or drawn again, for example at
// another width. NO when the effect cannot follow.
- (BOOL)relayoutWithSnapshot:(nonnull ATRGlyphSnapshot *)snapshot;
// Removes everything the effect put on screen. The completion is not called.
- (void)cancel;

@end

typedef NS_ENUM(uint8_t, ATRNumericTextDirection) {
    // New glyphs come in from above, old ones leave downward.
    ATRNumericTextDirectionDownward,
    // New glyphs come in from below, old ones leave upward.
    ATRNumericTextDirectionUpward,
};

// What glyphs already on screen hold on to when the view moves while its
// text changes.
typedef NS_ENUM(uint8_t, ATRNumericTextAnchoring) {
    // Their place on screen: a kept glyph slides from where it was.
    ATRNumericTextAnchoringScreen,
    // The view: glyphs move with it at once and only travel inside it.
    ATRNumericTextAnchoringView,
};

// SwiftUI's numericText content transition. Glyphs that changed roll out and
// in one after another behind a blur; kept glyphs slide to their new places.
// Drawn with Metal in an overlay that exists only while the effect runs.
// iOS only: on macOS `begin` returns NO.
@interface ATRNumericTextTransition : NSObject <ATRTextTransitionEffect>

@property (nonatomic) ATRNumericTextDirection direction;
@property (nonatomic) ATRNumericTextAnchoring anchoring;

// Builds the Metal pipeline a first use would otherwise build on the main
// thread. Synchronous and safe on any thread.
+ (ATRTextTransitionPrewarmResult)prewarm;

// How many glyphs stay at the start and at the end of the text when `from`
// becomes `to`; everything between is replaced. Once a change reaches into
// a number, the rest of that number rolls with it.
+ (void)keptCountsFrom:(nullable const ATRGlyphAtom *)from
                 count:(NSUInteger)fromCount
                    to:(nullable const ATRGlyphAtom *)to
                 count:(NSUInteger)toCount
                prefix:(nonnull NSUInteger *)prefix
                suffix:(nonnull NSUInteger *)suffix;

@end
