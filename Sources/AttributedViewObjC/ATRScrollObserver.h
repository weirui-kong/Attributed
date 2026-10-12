// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#import "ATRTypes.h"

// Follows the first scroll view enclosing a view and reports its scrolling:
// KVO on contentOffset on iOS, clip-view bounds notifications on macOS.
@interface ATRScrollObserver : NSObject

@property (nonatomic, readonly, weak, nullable) ATRPlatformView *scrollView;

- (nonnull instancetype)initWithChangeHandler:(nonnull void (^)(void))changeHandler NS_DESIGNATED_INITIALIZER;
- (nonnull instancetype)init NS_UNAVAILABLE;

// Switches to the first scroll view enclosing `view`, or stops observing when
// there is none. Observing the same scroll view again is a no-op.
- (void)observeFirstScrollViewEnclosing:(nonnull ATRPlatformView *)view;
- (void)stop;

// The visible part of `view`'s bounds: the observed scroll view's viewport,
// else the window's; CGRectNull when neither is known.
- (CGRect)visibleRegionOfView:(nonnull ATRPlatformView *)view;

@end
