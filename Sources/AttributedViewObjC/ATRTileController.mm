// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#import "ATRTileController.h"

#include <algorithm>
#include <cmath>
#include <unordered_map>

#if !__has_feature(objc_arc)
#error "AttributedViewObjC must be compiled with ARC."
#endif

namespace {

constexpr CGFloat kDefaultTileHeight = 256;

// Each render request stamps its layer; only the latest request may install
// its bitmap. Content generations alone can't tell apart two requests for
// the same layer with the same content, such as after a height change.
NSString *const kRequestKey = @"ATRRenderRequest";

NSDictionary<NSString *, id<CAAction>> *disabledActions() {
    static NSDictionary<NSString *, id<CAAction>> *actions = @{
        @"contents": NSNull.null,
        @"position": NSNull.null,
        @"bounds": NSNull.null,
        @"transform": NSNull.null,
        @"contentsScale": NSNull.null,
    };
    return actions;
}

} // namespace

@implementation ATRTileController {
    __weak CALayer *_hostLayer;
    uint64_t _generation;
    uint64_t _requestCounter;
    CGFloat _scale;
    CALayer *_surface;
    uint64_t _surfaceGeneration;
    CGRect _surfaceRect;
    NSMutableDictionary<NSNumber *, CALayer *> *_tiles;
    std::unordered_map<NSInteger, uint64_t> _tileGenerations;
}

- (instancetype)initWithHostLayer:(CALayer *)hostLayer {
    self = [super init];

    if (self) {
        _hostLayer = hostLayer;
        _tileHeight = kDefaultTileHeight;
        _generation = 1;
        _tiles = [NSMutableDictionary dictionary];
    }

    return self;
}

- (void)setTileHeight:(CGFloat)tileHeight {
    CGFloat value = tileHeight > 0 ? tileHeight : kDefaultTileHeight;

    if (_tileHeight != value) {
        _tileHeight = value;
        [self removeTiles];
    }
}

- (void)invalidateContent {
    _generation += 1;
}

- (void)updateScale:(CGFloat)scale {
    if (scale != _scale) {
        _scale = scale;
        _generation += 1;
    }
}

- (CALayer *)makeLayer {
    CALayer *layer = [CALayer layer];
    layer.actions = disabledActions();
    [_hostLayer addSublayer:layer];

#if TARGET_OS_OSX
    // In AppKit's flipped layer tree, contents render upside down;
    // counter-flip so bitmaps drawn top-down stay upright. UIKit layers
    // already display them upright.
    if (layer.contentsAreFlipped) {
        layer.affineTransform = CGAffineTransformMakeScale(1, -1);
    }
#endif

    return layer;
}

- (void)renderSurfaceInBounds:(CGRect)bounds scale:(CGFloat)scale snapshot:(ATRSnapshotProvider)snapshot {
    [self updateScale:scale];
    [self removeTiles];

    if (!_surface) {
        _surface = [self makeLayer];
    }

    if (_surfaceGeneration == _generation && CGRectEqualToRect(_surfaceRect, bounds)) {
        return;
    }

    _surfaceGeneration = _generation;
    _surfaceRect = bounds;
    [self renderRect:bounds intoLayer:_surface snapshot:snapshot()];
}

- (void)renderTilesInBounds:(CGRect)bounds
              visibleRegion:(CGRect)visibleRegion
                      scale:(CGFloat)scale
                   snapshot:(ATRSnapshotProvider)snapshot {
    [self updateScale:scale];
    [_surface removeFromSuperlayer];
    _surface = nil;
    _surfaceGeneration = 0;

    CGFloat tileHeight = _tileHeight;
    auto tileCount = static_cast<NSInteger>(std::ceil(CGRectGetHeight(bounds) / tileHeight));
    NSInteger firstNeeded = 0;
    NSInteger lastNeeded = -1;

    if (!CGRectIsNull(visibleRegion) && !CGRectIsEmpty(visibleRegion) && tileCount > 0) {
        firstNeeded = std::max<NSInteger>(0, std::floor(CGRectGetMinY(visibleRegion) / tileHeight) - 1);
        lastNeeded = std::min<NSInteger>(tileCount - 1, std::ceil(CGRectGetMaxY(visibleRegion) / tileHeight));
    }

    // Tiles stay a little longer than they are prefetched, so scrolling back
    // and forth doesn't redraw them.
    for (NSNumber *key in _tiles.allKeys) {
        NSInteger index = key.integerValue;

        if (index < firstNeeded - 1 || index > lastNeeded + 1 || index >= tileCount) {
            [_tiles[key] removeFromSuperlayer];
            [_tiles removeObjectForKey:key];
            _tileGenerations.erase(index);
        }
    }

    ATRRenderSnapshot *resolved = nil;

    for (NSInteger index = firstNeeded; index <= lastNeeded; ++index) {
        CALayer *layer = _tiles[@(index)];

        if (!layer) {
            layer = [self makeLayer];
            _tiles[@(index)] = layer;
        } else if (_tileGenerations[index] == _generation) {
            continue;
        }

        CGFloat top = index * tileHeight;
        CGRect rect = CGRectMake(0, top, CGRectGetWidth(bounds), std::min(tileHeight, CGRectGetHeight(bounds) - top));
        _tileGenerations[index] = _generation;
        resolved = resolved ?: snapshot();
        [self renderRect:rect intoLayer:layer snapshot:resolved];
    }
}

- (void)renderRect:(CGRect)rect intoLayer:(CALayer *)layer snapshot:(ATRRenderSnapshot *)snapshot {
    CGFloat scale = _scale;
    layer.bounds = CGRectMake(0, 0, CGRectGetWidth(rect), CGRectGetHeight(rect));
    layer.position = CGPointMake(CGRectGetMidX(rect), CGRectGetMidY(rect));
    layer.contentsScale = scale;

    if (!_rendersAsynchronously) {
        // Supersedes any asynchronous request still in flight for the layer.
        [layer setValue:nil forKey:kRequestKey];
        layer.contents = (__bridge_transfer id)[snapshot newImageForRect:rect scale:scale];
        return;
    }

    _requestCounter += 1;
    NSNumber *request = @(_requestCounter);
    [layer setValue:request forKey:kRequestKey];
    __weak CALayer *weakLayer = layer;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        CGImageRef image = [snapshot newImageForRect:rect scale:scale];

        dispatch_async(dispatch_get_main_queue(), ^{
            CALayer *target = weakLayer;

            if ([[target valueForKey:kRequestKey] isEqual:request]) {
                target.contents = (__bridge id)image;
            }

            if (image) {
                CGImageRelease(image);
            }
        });
    });
}

- (void)removeTiles {
    for (CALayer *layer in _tiles.allValues) {
        [layer removeFromSuperlayer];
    }

    [_tiles removeAllObjects];
    _tileGenerations.clear();
}

- (void)removeAllLayers {
    [self removeTiles];
    [_surface removeFromSuperlayer];
    _surface = nil;
    _surfaceGeneration = 0;
}

- (NSIndexSet *)renderedTileIndexes {
    NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];

    for (NSNumber *key in _tiles) {
        [indexes addIndex:key.unsignedIntegerValue];
    }

    return indexes;
}

@end
