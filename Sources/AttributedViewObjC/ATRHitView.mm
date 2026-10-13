// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#import "ATRHitView.h"

#include <vector>

#if !__has_feature(objc_arc)
#error "AttributedEngineObjC must be compiled with ARC."
#endif

namespace {

CGRect rectValue(NSValue *value) {
    CGRect rect = CGRectZero;
    [value getValue:&rect size:sizeof(rect)];
    return rect;
}

} // namespace

@implementation ATRHitView {
    // In the superview's coordinates.
    std::vector<CGRect> _regions;
}

- (instancetype)initWithInteractionSet:(uint32_t)interactionSet {
    self = [super initWithFrame:CGRectZero];

    if (self) {
        _interactionSet = interactionSet;
        _bindings = @[];
#if !TARGET_OS_OSX
        self.backgroundColor = UIColor.clearColor;
        self.opaque = NO;
#endif
    }

    return self;
}

#if TARGET_OS_OSX
- (BOOL)isFlipped {
    return YES;
}
#endif

- (void)setRegions:(NSArray<NSValue *> *)regions {
    _regions.clear();
    CGRect frame = CGRectNull;

    for (NSValue *value in regions) {
        CGRect rect = rectValue(value);
        _regions.push_back(rect);
        frame = CGRectUnion(frame, rect);
    }

    self.frame = CGRectIsNull(frame) ? CGRectZero : frame;
}

- (BOOL)containsPointInSuperview:(CGPoint)point {
    for (const CGRect &rect : _regions) {
        if (CGRectContainsPoint(rect, point)) {
            return YES;
        }
    }

    return NO;
}

#if TARGET_OS_OSX
// AppKit passes the point in the superview's coordinates.
- (NSView *)hitTest:(NSPoint)point {
    return [self containsPointInSuperview:point] ? self : nil;
}
#else
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    return [self containsPointInSuperview:[self convertPoint:point toView:self.superview]];
}
#endif

- (void)installBindings:(NSArray<ATRGestureBinding *> *)bindings {
    for (ATRGestureBinding *binding in _bindings) {
        [self removeGestureRecognizer:binding.recognizer];
    }

    _bindings = [bindings copy];

    for (ATRGestureBinding *binding in _bindings) {
        [self addGestureRecognizer:binding.recognizer];
    }
}

- (BOOL)isRecognizing {
    for (ATRGestureBinding *binding in _bindings) {
#if TARGET_OS_OSX
        if (binding.recognizer.state != NSGestureRecognizerStatePossible) {
#else
        if (binding.recognizer.state != UIGestureRecognizerStatePossible) {
#endif
            return YES;
        }
    }

    return NO;
}

- (void)triggerInteraction:(uint32_t)interaction atLocation:(CGPoint)location {
    CGPoint inSuperview = self.superview ? [self convertPoint:location toView:self.superview] : location;
    [_delegate hitView:self didTriggerInteraction:interaction atLocation:inSuperview];
}

@end
