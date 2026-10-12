// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#import <QuartzCore/QuartzCore.h>

#import "ATRRenderSnapshot.h"
#import "ATRTypes.h"

// Called only when something must actually be drawn.
typedef ATRRenderSnapshot *_Nonnull (^ATRSnapshotProvider)(void);

// Owns the layers a text view draws into: one surface for the whole bounds,
// or horizontal tiles near the visible region. Results are tagged with a
// content generation so late asynchronous drawing for stale content is
// dropped.
@interface ATRTileController : NSObject

// 256 by default.
@property (nonatomic) CGFloat tileHeight;
@property (nonatomic) BOOL rendersAsynchronously;
@property (nonatomic, readonly, nonnull) NSIndexSet *renderedTileIndexes;

- (nonnull instancetype)initWithHostLayer:(nonnull CALayer *)hostLayer NS_DESIGNATED_INITIALIZER;
- (nonnull instancetype)init NS_UNAVAILABLE;

// Marks everything drawn so far as stale; the next render call redraws.
- (void)invalidateContent;

- (void)renderSurfaceInBounds:(CGRect)bounds
                        scale:(CGFloat)scale
                     snapshot:(nonnull ATRSnapshotProvider)snapshot;

// Keeps tiles for `visibleRegion` plus one tile of lookahead on each side,
// and evicts tiles more than one tile beyond that. A null region keeps none.
- (void)renderTilesInBounds:(CGRect)bounds
              visibleRegion:(CGRect)visibleRegion
                      scale:(CGFloat)scale
                   snapshot:(nonnull ATRSnapshotProvider)snapshot;

- (void)removeAllLayers;

@end
