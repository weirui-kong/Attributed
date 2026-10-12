// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#import "ATRHitViewManager.h"

#import "ATRDocument.h"

#if !__has_feature(objc_arc)
#error "AttributedViewObjC must be compiled with ARC."
#endif

@implementation ATRHitViewManager {
    __weak ATRPlatformView *_containerView;
    NSMutableDictionary<NSNumber *, ATRHitView *> *_hitViewsBySet;
}

- (instancetype)initWithContainerView:(ATRPlatformView *)containerView {
    self = [super init];

    if (self) {
        _containerView = containerView;
        _hitViewsBySet = [NSMutableDictionary dictionary];
        _registry = [ATRGestureRecognizerRegistry defaultRegistry];
        _policy = [[ATRDefaultGesturePolicy alloc] init];
    }

    return self;
}

- (NSArray<ATRHitView *> *)hitViews {
    return _hitViewsBySet.allValues;
}

- (void)removeAll {
    for (ATRHitView *hitView in _hitViewsBySet.allValues) {
        [hitView removeFromSuperview];
    }

    [_hitViewsBySet removeAllObjects];
}

- (void)updateWithLayout:(ATRTextLayout *)layout {
    NSMutableDictionary<NSNumber *, NSMutableArray<NSValue *> *> *regionsBySet = [NSMutableDictionary dictionary];

    for (NSUInteger index = 0; index < layout.hitRegionCount; ++index) {
        ATRHitRegion region = [layout hitRegionAtIndex:index];
        NSMutableArray<NSValue *> *regions = regionsBySet[@(region.interactionSet)];

        if (!regions) {
            regions = [NSMutableArray array];
            regionsBySet[@(region.interactionSet)] = regions;
        }

        [regions addObject:[NSValue valueWithBytes:&region.rect objCType:@encode(CGRect)]];
    }

    for (NSNumber *key in _hitViewsBySet.allKeys) {
        if (!regionsBySet[key]) {
            [_hitViewsBySet[key] removeFromSuperview];
            [_hitViewsBySet removeObjectForKey:key];
        }
    }

    [regionsBySet enumerateKeysAndObjectsUsingBlock:^(NSNumber *key, NSArray<NSValue *> *regions, BOOL *stop) {
        ATRHitView *hitView = self->_hitViewsBySet[key];

        if (!hitView) {
            hitView = [self makeHitViewForSet:key.unsignedIntValue layout:layout];
            self->_hitViewsBySet[key] = hitView;
            [self->_containerView addSubview:hitView];
        }

        [hitView setRegions:regions];
    }];
}

- (ATRHitView *)makeHitViewForSet:(uint32_t)interactionSet layout:(ATRTextLayout *)layout {
    ATRHitView *hitView = [[ATRHitView alloc] initWithInteractionSet:interactionSet];
    hitView.delegate = _delegate;
    __weak ATRHitView *weakHitView = hitView;
    NSMutableArray<ATRGestureBinding *> *bindings = [NSMutableArray array];

    for (NSNumber *interaction in [layout interactionsInSet:interactionSet]) {
        ATRGesture gesture = [layout.document gestureForInteraction:interaction.unsignedIntValue];
        id<ATRGestureRecognizerFactory> factory = [_registry factoryForKind:gesture.kind];

        if (!factory) {
            continue;
        }

        [bindings addObject:[factory bindingForGesture:gesture
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
