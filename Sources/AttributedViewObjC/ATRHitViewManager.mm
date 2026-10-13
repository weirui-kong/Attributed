// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#import "ATRHitViewManager.h"

#import "ATRDocument.h"

#include <algorithm>
#include <unordered_map>
#include <vector>

#if !__has_feature(objc_arc)
#error "AttributedViewObjC must be compiled with ARC."
#endif

namespace {

struct IndexedRegion {
    CGRect rect;
    uint32_t interactionSet;
};

} // namespace

@implementation ATRHitViewManager {
    __weak ATRPlatformView *_containerView;
    ATRTextLayout *_layout;
    // Sorted by minY, so a visible rect is found by binary search.
    std::vector<IndexedRegion> _regions;
    CGFloat _tallestRegion;
    BOOL _hasVisibleRect;
    CGRect _visibleRect;
    NSMutableDictionary<NSNumber *, ATRHitView *> *_visibleBySet;
    NSMutableDictionary<NSString *, NSMutableArray<ATRHitView *> *> *_pool;
    // Interaction sets are stable for one document, so signatures outlive
    // relayouts and are cleared only by removeAll.
    NSMutableDictionary<NSNumber *, NSString *> *_signatures;
}

- (instancetype)initWithContainerView:(ATRPlatformView *)containerView {
    self = [super init];

    if (self) {
        _containerView = containerView;
        _visibleBySet = [NSMutableDictionary dictionary];
        _pool = [NSMutableDictionary dictionary];
        _signatures = [NSMutableDictionary dictionary];
        _registry = [ATRGestureRecognizerRegistry defaultRegistry];
        _policy = [[ATRDefaultGesturePolicy alloc] init];
    }

    return self;
}

- (NSArray<ATRHitView *> *)hitViews {
    return _visibleBySet.allValues;
}

- (NSUInteger)reusableHitViewCount {
    NSUInteger count = 0;

    for (NSArray<ATRHitView *> *views in _pool.allValues) {
        count += views.count;
    }

    return count;
}

- (void)removeAll {
    for (ATRHitView *hitView in _visibleBySet.allValues) {
        [hitView removeFromSuperview];
    }

    for (NSArray<ATRHitView *> *views in _pool.allValues) {
        for (ATRHitView *hitView in views) {
            [hitView removeFromSuperview];
        }
    }

    [_visibleBySet removeAllObjects];
    [_pool removeAllObjects];
    [_signatures removeAllObjects];
    _layout = nil;
    _regions.clear();
    _hasVisibleRect = NO;
}

- (void)updateWithLayout:(ATRTextLayout *)layout visibleRect:(CGRect)visibleRect {
    _layout = layout;
    _regions.clear();
    _regions.reserve(layout.hitRegionCount);
    _tallestRegion = 0;

    for (NSUInteger index = 0; index < layout.hitRegionCount; ++index) {
        ATRHitRegion region = [layout hitRegionAtIndex:index];
        _regions.push_back({region.rect, region.interactionSet});
        _tallestRegion = std::max(_tallestRegion, CGRectGetHeight(region.rect));
    }

    std::stable_sort(_regions.begin(), _regions.end(), [](const IndexedRegion &a, const IndexedRegion &b) {
        return CGRectGetMinY(a.rect) < CGRectGetMinY(b.rect);
    });

    _hasVisibleRect = NO;
    [self updateVisibleRect:visibleRect];
}

- (void)updateVisibleRect:(CGRect)visibleRect {
    if (!_layout || (_hasVisibleRect && CGRectEqualToRect(visibleRect, _visibleRect))) {
        return;
    }

    _hasVisibleRect = YES;
    _visibleRect = visibleRect;

    // Visible regions grouped by set, in index order.
    std::unordered_map<uint32_t, std::vector<CGRect>> regionsBySet;

    if (!CGRectIsNull(visibleRect)) {
        BOOL everything = CGRectIsInfinite(visibleRect);
        auto begin = _regions.begin();

        if (!everything) {
            // A region starting above the rect can still reach into it, but
            // no further than the tallest region.
            CGFloat lowest = CGRectGetMinY(visibleRect) - _tallestRegion;
            begin = std::lower_bound(_regions.begin(), _regions.end(), lowest, [](const IndexedRegion &region, CGFloat y) {
                return CGRectGetMinY(region.rect) < y;
            });
        }

        for (auto it = begin; it != _regions.end(); ++it) {
            if (!everything) {
                if (CGRectGetMinY(it->rect) > CGRectGetMaxY(visibleRect)) {
                    break;
                }

                if (!CGRectIntersectsRect(it->rect, visibleRect)) {
                    continue;
                }
            }

            regionsBySet[it->interactionSet].push_back(it->rect);
        }
    }

    // Recycle the sets that left first, so entering sets can take them over.
    for (NSNumber *key in _visibleBySet.allKeys) {
        ATRHitView *hitView = _visibleBySet[key];

        if (regionsBySet.count(key.unsignedIntValue) || hitView.isRecognizing) {
            continue;
        }

        [_visibleBySet removeObjectForKey:key];
        hitView.hidden = YES;
        [[self poolFor:[self signatureForSet:key.unsignedIntValue]] addObject:hitView];
    }

    for (auto &[set, rects] : regionsBySet) {
        ATRHitView *hitView = _visibleBySet[@(set)];

        if (!hitView) {
            hitView = [self dequeueHitViewForSet:set];
            _visibleBySet[@(set)] = hitView;
        }

        NSMutableArray<NSValue *> *values = [NSMutableArray arrayWithCapacity:rects.size()];

        for (const CGRect &rect : rects) {
            [values addObject:[NSValue valueWithBytes:&rect objCType:@encode(CGRect)]];
        }

        [hitView setRegions:values];
    }
}

- (NSMutableArray<ATRHitView *> *)poolFor:(NSString *)signature {
    NSMutableArray<ATRHitView *> *views = _pool[signature];

    if (!views) {
        views = [NSMutableArray array];
        _pool[signature] = views;
    }

    return views;
}

- (NSArray<NSNumber *> *)interactionsInSet:(uint32_t)interactionSet {
    NSMutableArray<NSNumber *> *interactions = [NSMutableArray array];

    for (NSNumber *interaction in [_layout interactionsInSet:interactionSet]) {
        ATRGesture gesture = [_layout.document gestureForInteraction:interaction.unsignedIntValue];

        if ([_registry factoryForKind:gesture.kind]) {
            [interactions addObject:interaction];
        }
    }

    return interactions;
}

- (NSString *)signatureForSet:(uint32_t)interactionSet {
    NSString *signature = _signatures[@(interactionSet)];

    if (signature) {
        return signature;
    }

    NSMutableString *built = [NSMutableString string];

    for (NSNumber *interaction in [self interactionsInSet:interactionSet]) {
        ATRGesture gesture = [_layout.document gestureForInteraction:interaction.unsignedIntValue];
        [built appendFormat:@"%d:%u:%a;", gesture.kind, gesture.tapCount, gesture.minimumPressDuration];
    }

    _signatures[@(interactionSet)] = built;
    return built;
}

- (ATRHitView *)dequeueHitViewForSet:(uint32_t)interactionSet {
    NSMutableArray<ATRHitView *> *pool = _pool[[self signatureForSet:interactionSet]];
    ATRHitView *hitView = pool.lastObject;

    if (!hitView) {
        hitView = [self makeHitViewForSet:interactionSet];
        [_containerView addSubview:hitView];
        return hitView;
    }

    [pool removeLastObject];
    // Bindings are in the same order as the set's interactions, because
    // equal signatures list the same gestures in the same order.
    NSArray<NSNumber *> *interactions = [self interactionsInSet:interactionSet];
    NSArray<ATRGestureBinding *> *bindings = hitView.bindings;

    for (NSUInteger index = 0; index < bindings.count; ++index) {
        bindings[index].interaction = interactions[index].unsignedIntValue;
    }

    hitView.interactionSet = interactionSet;
    hitView.hidden = NO;
    return hitView;
}

- (ATRHitView *)makeHitViewForSet:(uint32_t)interactionSet {
    ATRHitView *hitView = [[ATRHitView alloc] initWithInteractionSet:interactionSet];
    hitView.delegate = _delegate;
    __weak ATRHitView *weakHitView = hitView;
    NSMutableArray<ATRGestureBinding *> *bindings = [NSMutableArray array];

    for (NSNumber *interaction in [self interactionsInSet:interactionSet]) {
        ATRGesture gesture = [_layout.document gestureForInteraction:interaction.unsignedIntValue];
        [bindings addObject:[[_registry factoryForKind:gesture.kind]
                                bindingForGesture:gesture
                                      interaction:interaction.unsignedIntValue
                                          handler:^(uint32_t value, CGPoint location) {
                                              [weakHitView triggerInteraction:value atLocation:location];
                                          }]];
    }

    [_policy configureBindings:bindings];
    [hitView installBindings:bindings];
    return hitView;
}

@end
