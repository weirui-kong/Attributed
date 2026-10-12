// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#import "ATRGestures.h"
#import "ATRTypes.h"

@class ATRHitView;

@protocol ATRHitViewDelegate <NSObject>

// `location` is in the hit view's superview coordinates.
- (void)hitView:(nonnull ATRHitView *)hitView
    didTriggerInteraction:(uint32_t)interaction
               atLocation:(CGPoint)location;

@end

// A transparent view over the text of one interaction set. It hosts the
// set's gesture recognizers and accepts touches only inside its regions,
// so overlapping hit views of different sets don't steal each other's
// touches.
@interface ATRHitView : ATRPlatformView

@property (nonatomic, readonly) uint32_t interactionSet;
@property (nonatomic, readonly, nonnull) NSArray<ATRGestureBinding *> *bindings;
@property (nonatomic, weak, nullable) id<ATRHitViewDelegate> delegate;

- (nonnull instancetype)initWithInteractionSet:(uint32_t)interactionSet NS_DESIGNATED_INITIALIZER;
- (nonnull instancetype)initWithFrame:(CGRect)frame NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(nonnull NSCoder *)coder NS_UNAVAILABLE;

// Regions are in the superview's coordinates; the frame becomes their union.
- (void)setRegions:(nonnull NSArray<NSValue *> *)regions;
- (BOOL)containsPointInSuperview:(CGPoint)point;

// Replaces the installed bindings.
- (void)installBindings:(nonnull NSArray<ATRGestureBinding *> *)bindings;

// Reports `interaction` to the delegate; `location` is in this view's
// coordinates.
- (void)triggerInteraction:(uint32_t)interaction atLocation:(CGPoint)location;

@end
