// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#import "ATRGestures.h"
#import "ATRHitView.h"
#import "ATRTextLayout.h"

// Creates, moves, and removes the hit views of a text view. Hit views are
// keyed by interaction set, which is stable for one document, so a relayout
// only moves their regions. Recognizers come from the registry and are wired
// by the policy.
@interface ATRHitViewManager : NSObject

@property (nonatomic, strong, nonnull) ATRGestureRecognizerRegistry *registry;
@property (nonatomic, strong, nonnull) id<ATRGesturePolicy> policy;
@property (nonatomic, weak, nullable) id<ATRHitViewDelegate> delegate;
@property (nonatomic, readonly, nonnull) NSArray<ATRHitView *> *hitViews;

- (nonnull instancetype)initWithContainerView:(nonnull ATRPlatformView *)containerView NS_DESIGNATED_INITIALIZER;
- (nonnull instancetype)init NS_UNAVAILABLE;

- (void)updateWithLayout:(nonnull ATRTextLayout *)layout;
- (void)removeAll;

@end
