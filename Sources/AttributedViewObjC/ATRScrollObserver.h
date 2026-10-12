// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#import "ATRTypes.h"

// Follows the first scroll view enclosing a view and reports its scrolling:
// KVO on contentOffset on iOS, clip-view bounds notifications on macOS.
//
// It observes only while the view is in a window, and holds the scroll view
// strongly meanwhile. A view in a window is retained by the window's
// hierarchy anyway, and leaving a window is reported to every descendant,
// so the reference never outlives the hierarchy and observation can always
// be removed from a live object.
@interface ATRScrollObserver : NSObject

@property (nonatomic, readonly, nullable) ATRPlatformView *scrollView;

- (nonnull instancetype)initWithChangeHandler:(nonnull void (^)(void))changeHandler NS_DESIGNATED_INITIALIZER;
- (nonnull instancetype)init NS_UNAVAILABLE;

// Switches to the first scroll view enclosing `view`, or stops when `view`
// has no window or no enclosing scroll view. Call it when the view moves to
// a window. An ancestor moved between scroll views within the same window
// is not followed until the view next moves to a window.
- (void)observeFirstScrollViewEnclosing:(nonnull ATRPlatformView *)view;
- (void)stop;

// The visible part of `view`'s bounds: the observed scroll view's viewport,
// else the window's; CGRectNull when neither is known.
- (CGRect)visibleRegionOfView:(nonnull ATRPlatformView *)view;

@end
