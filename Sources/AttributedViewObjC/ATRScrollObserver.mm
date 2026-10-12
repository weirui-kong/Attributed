// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#import "ATRScrollObserver.h"

#if !__has_feature(objc_arc)
#error "AttributedViewObjC must be compiled with ARC."
#endif

static void *ATRContentOffsetContext = &ATRContentOffsetContext;

@implementation ATRScrollObserver {
    void (^_changeHandler)(void);
#if !TARGET_OS_OSX
    // KVO must be removed from the scroll view even while it deallocates,
    // when the weak reference already reads nil.
    __unsafe_unretained UIScrollView *_scrollViewForRemoval;
#endif
}

- (instancetype)initWithChangeHandler:(void (^)(void))changeHandler {
    self = [super init];

    if (self) {
        _changeHandler = [changeHandler copy];
    }

    return self;
}

- (void)dealloc {
    [self stop];
}

- (ATRPlatformView *)firstScrollViewEnclosing:(ATRPlatformView *)view {
#if TARGET_OS_OSX
    return view.enclosingScrollView;
#else
    for (UIView *ancestor = view.superview; ancestor; ancestor = ancestor.superview) {
        if ([ancestor isKindOfClass:UIScrollView.class]) {
            return ancestor;
        }
    }

    return nil;
#endif
}

- (void)observeFirstScrollViewEnclosing:(ATRPlatformView *)view {
    ATRPlatformView *scrollView = [self firstScrollViewEnclosing:view];

    if (scrollView == _scrollView) {
        return;
    }

    [self stop];

    if (!scrollView) {
        return;
    }

    _scrollView = scrollView;

#if TARGET_OS_OSX
    NSClipView *clipView = ((NSScrollView *)scrollView).contentView;
    clipView.postsBoundsChangedNotifications = YES;
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(clipViewBoundsDidChange:)
                                               name:NSViewBoundsDidChangeNotification
                                             object:clipView];
#else
    _scrollViewForRemoval = (UIScrollView *)scrollView;
    [scrollView addObserver:self
                 forKeyPath:@"contentOffset"
                    options:NSKeyValueObservingOptionNew
                    context:ATRContentOffsetContext];
#endif
}

- (void)stop {
#if TARGET_OS_OSX
    [NSNotificationCenter.defaultCenter removeObserver:self
                                                  name:NSViewBoundsDidChangeNotification
                                                object:nil];
#else
    [_scrollViewForRemoval removeObserver:self forKeyPath:@"contentOffset" context:ATRContentOffsetContext];
    _scrollViewForRemoval = nil;
#endif
    _scrollView = nil;
}

- (CGRect)visibleRegionOfView:(ATRPlatformView *)view {
    ATRPlatformView *scrollView = _scrollView;
    CGRect region = CGRectNull;

    if (scrollView) {
#if TARGET_OS_OSX
        NSClipView *clipView = ((NSScrollView *)scrollView).contentView;
        region = [view convertRect:clipView.bounds fromView:clipView];
#else
        region = [view convertRect:scrollView.bounds fromView:scrollView];
#endif
    } else if (view.window) {
#if TARGET_OS_OSX
        region = view.visibleRect;
#else
        region = [view convertRect:view.window.bounds fromView:nil];
#endif
    }

    return CGRectIsNull(region) ? CGRectNull : CGRectIntersection(region, view.bounds);
}

#if TARGET_OS_OSX
- (void)clipViewBoundsDidChange:(NSNotification *)notification {
    _changeHandler();
}
#else
- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey, id> *)change
                       context:(void *)context {
    if (context != ATRContentOffsetContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }

    _changeHandler();
}
#endif

@end
