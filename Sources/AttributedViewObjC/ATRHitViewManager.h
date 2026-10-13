// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#import "ATRGestures.h"
#import "ATRHitView.h"
#import "ATRTextLayout.h"

// Creates, moves, hides, and reuses the hit views of a text view, on the main
// thread only. Recognizers come from the registry and are wired by the
// policy.
//
// Only interaction sets with a region inside the visible rect get a hit
// view. A hit view whose set leaves the rect is hidden and pooled by gesture
// signature (the kinds and parameters of its bindings, in order); a set with
// the same signature takes it over with its recognizers and their
// dependencies intact, and only the bindings' interaction IDs change. Hit
// views in the middle of recognizing a gesture are never reused.
@interface ATRHitViewManager : NSObject

@property (nonatomic, strong, nonnull) ATRGestureRecognizerRegistry *registry;
@property (nonatomic, strong, nonnull) id<ATRGesturePolicy> policy;
@property (nonatomic, weak, nullable) id<ATRHitViewDelegate> delegate;
// The visible hit views.
@property (nonatomic, readonly, nonnull) NSArray<ATRHitView *> *hitViews;
// Hidden hit views waiting for reuse.
@property (nonatomic, readonly) NSUInteger reusableHitViewCount;

- (nonnull instancetype)initWithContainerView:(nonnull ATRPlatformView *)containerView NS_DESIGNATED_INITIALIZER;
- (nonnull instancetype)init NS_UNAVAILABLE;

// Indexes the layout's hit regions and shows the sets inside `visibleRect`.
// CGRectInfinite shows every set; CGRectNull shows none.
- (void)updateWithLayout:(nonnull ATRTextLayout *)layout visibleRect:(CGRect)visibleRect;
// Shows the sets inside `visibleRect` for the current layout. Cheap when the
// rect is unchanged.
- (void)updateVisibleRect:(CGRect)visibleRect;
// Removes every hit view, pooled ones included. Needed when the document,
// registry, or policy changes.
- (void)removeAll;

@end
