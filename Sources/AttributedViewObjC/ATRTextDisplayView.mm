// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#import "ATRTextDisplayView.h"

#import <QuartzCore/QuartzCore.h>

#import "ATRRenderSnapshot.h"

#include <cmath>
#include <unordered_map>

#if !__has_feature(objc_arc)
#error "AttributedEngineObjC must be compiled with ARC."
#endif

static void *ATRContentOffsetContext = &ATRContentOffsetContext;

namespace {

constexpr CGFloat kDefaultTileHeight = 256;

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

// Returns a +1 image with orientation applied, or NULL.
CGImageRef copyCGImage(ATRPlatformImage *image) CF_RETURNS_RETAINED {
#if TARGET_OS_OSX
    CGImageRef result = [image CGImageForProposedRect:nullptr context:nil hints:nil];
    return result ? CGImageRetain(result) : nullptr;
#else
    if (image.imageOrientation == UIImageOrientationUp && image.CGImage) {
        return CGImageRetain(image.CGImage);
    }

    // CGImages carry no orientation; bake it in.
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = image.scale;
    UIImage *upright = [[[UIGraphicsImageRenderer alloc] initWithSize:image.size format:format]
        imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [image drawInRect:CGRectMake(0, 0, image.size.width, image.size.height)];
        }];
    return upright.CGImage ? CGImageRetain(upright.CGImage) : nullptr;
#endif
}

} // namespace

@interface ATRTextDisplayView () <ATRHitViewDelegate>
@end

@implementation ATRTextDisplayView {
    ATRTextLayout *_textLayout;
    ATRTextLayout *_measureLayout;
    BOOL _layoutValid;
    // Loaded sizes of adaptive AsyncImages, keyed by attachment ID.
    NSMutableDictionary<NSNumber *, NSValue *> *_contentSizes;
    NSMutableDictionary<NSNumber *, id> *_images;
    ATRRenderSnapshot *_snapshot;
    // Bumped whenever drawn content becomes stale; late asynchronous
    // results from older generations are dropped.
    uint64_t _generation;
    CALayer *_contentLayer;
    uint64_t _contentGeneration;
    CGRect _contentRect;
    NSMutableDictionary<NSNumber *, CALayer *> *_tiles;
    std::unordered_map<NSUInteger, uint64_t> _tileGenerations;
    CGSize _reportedSize;
    NSMutableDictionary<NSNumber *, ATRHitView *> *_hitViewsBySet;
    CGFloat _renderedScale;
#if !TARGET_OS_OSX
    // KVO must be removed from the scroll view even while it deallocates,
    // when the weak reference already reads nil.
    __unsafe_unretained UIScrollView *_scrollViewForRemoval;
#endif
}

#pragma mark - Lifecycle

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];

    if (self) {
        [self commonInit];
    }

    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];

    if (self) {
        [self commonInit];
    }

    return self;
}

- (void)commonInit {
    _tileHeight = kDefaultTileHeight;
    _images = [NSMutableDictionary dictionary];
    _contentSizes = [NSMutableDictionary dictionary];
    _tiles = [NSMutableDictionary dictionary];
    _generation = 1;

    _hitViewsBySet = [NSMutableDictionary dictionary];
    _gestureRegistry = [ATRGestureRecognizerRegistry defaultRegistry];
    _gesturePolicy = [[ATRDefaultGesturePolicy alloc] init];

#if TARGET_OS_OSX
    self.wantsLayer = YES;
    self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawNever;
#else
    self.backgroundColor = UIColor.clearColor;
    self.opaque = NO;
#endif
}

- (void)dealloc {
    [self stopObservingScrollView];
}

#pragma mark - Configuration

- (void)setDocument:(ATRDocument *)document {
    if (_document == document) {
        return;
    }

    _document = document;
    [self removeHitViews];
    [_images removeAllObjects];
    [_contentSizes removeAllObjects];
    [self invalidateLayout];
}

- (void)setMaximumNumberOfLines:(NSUInteger)maximumNumberOfLines {
    if (_maximumNumberOfLines != maximumNumberOfLines) {
        _maximumNumberOfLines = maximumNumberOfLines;
        [self invalidateLayout];
    }
}

- (void)setTruncationToken:(NSString *)truncationToken {
    if (_truncationToken != truncationToken && ![_truncationToken isEqualToString:truncationToken]) {
        _truncationToken = [truncationToken copy];
        [self invalidateLayout];
    }
}

- (void)setLineHeightMode:(ATRLineHeightMode)lineHeightMode {
    if (_lineHeightMode != lineHeightMode) {
        _lineHeightMode = lineHeightMode;
        [self invalidateLayout];
    }
}

- (void)setViewportRenderingEnabled:(BOOL)viewportRenderingEnabled {
    if (_viewportRenderingEnabled == viewportRenderingEnabled) {
        return;
    }

    _viewportRenderingEnabled = viewportRenderingEnabled;
    [self removeAllLayers];
    [self updateScrollViewObservation];
    [self setNeedsLayoutPass];
}

- (void)setTileHeight:(CGFloat)tileHeight {
    CGFloat value = tileHeight > 0 ? tileHeight : kDefaultTileHeight;

    if (_tileHeight != value) {
        _tileHeight = value;
        [self removeAllLayers];
        [self setNeedsLayoutPass];
    }
}

- (void)setAppliesGradientToColorGlyphs:(BOOL)appliesGradientToColorGlyphs {
    if (_appliesGradientToColorGlyphs != appliesGradientToColorGlyphs) {
        _appliesGradientToColorGlyphs = appliesGradientToColorGlyphs;
        [self invalidateContent];
    }
}

- (void)setGestureRegistry:(ATRGestureRecognizerRegistry *)gestureRegistry {
    _gestureRegistry = gestureRegistry;
    [self removeHitViews];
    [self updateHitViews];
}

- (void)setGesturePolicy:(id<ATRGesturePolicy>)gesturePolicy {
    _gesturePolicy = gesturePolicy;
    [self removeHitViews];
    [self updateHitViews];
}

- (void)setImage:(ATRPlatformImage *)image forAttachment:(uint32_t)attachment {
    if (!_document || attachment >= _document.attachmentCount) {
        return;
    }

    if (CGImageRef cgImage = image ? copyCGImage(image) : nullptr) {
        _images[@(attachment)] = (__bridge_transfer id)cgImage;
    } else {
        [_images removeObjectForKey:@(attachment)];
    }

    ATRAttachmentDescriptor descriptor = [_document attachmentDescriptorAtIndex:attachment];

    if (descriptor.pipeline != ATRImagePipelineAsyncImage || descriptor.sizeKind != ATRAttachmentSizeKindAdaptive) {
        [self invalidateContent];
        return;
    }

    if (image && image.size.width > 0 && image.size.height > 0) {
        CGSize size = image.size;
        _contentSizes[@(attachment)] = [NSValue valueWithBytes:&size objCType:@encode(CGSize)];
    } else {
        [_contentSizes removeObjectForKey:@(attachment)];
    }

    [self invalidateLayout];
}

#pragma mark - Layout

- (ATRTextLayout *)textLayout {
    return _layoutValid ? _textLayout : nil;
}

- (ATRTextLayout *)layoutForWidth:(CGFloat)width {
    ATRTextContainer container = {
        width,
        INFINITY,
        static_cast<uint32_t>(MIN(_maximumNumberOfLines, (NSUInteger)UINT32_MAX)),
        _lineHeightMode,
    };
    return [_document layoutWithContainer:container
                          truncationToken:_truncationToken
                   attachmentContentSizes:_contentSizes];
}

- (CGSize)sizeThatFitsWidth:(CGFloat)width {
    if (!_document || !(width > 0)) {
        return CGSizeZero;
    }

    ATRTextLayout *layout = nil;

    if (_layoutValid && _textLayout.container.width == width) {
        layout = _textLayout;
    } else if (_measureLayout && _measureLayout.container.width == width) {
        layout = _measureLayout;
    } else {
        layout = [self layoutForWidth:width];
        _measureLayout = layout;
    }

    return CGSizeMake(std::ceil(layout.size.width), std::ceil(layout.size.height));
}

- (CGSize)intrinsicContentSize {
    CGFloat width = self.bounds.size.width;

    if (!_document || width <= 0) {
#if TARGET_OS_OSX
        return NSMakeSize(NSViewNoIntrinsicMetric, NSViewNoIntrinsicMetric);
#else
        return CGSizeMake(UIViewNoIntrinsicMetric, UIViewNoIntrinsicMetric);
#endif
    }

    return [self sizeThatFitsWidth:width];
}

- (void)invalidateLayout {
    _layoutValid = NO;
    _measureLayout = nil;
    [self invalidateIntrinsicContentSize];

    if (_contentSizeDidChangeHandler) {
        _contentSizeDidChangeHandler();
    }

    [self setNeedsLayoutPass];
}

- (void)invalidateContent {
    _generation += 1;
    _snapshot = nil;
    [self setNeedsLayoutPass];
}

- (void)setNeedsLayoutPass {
#if TARGET_OS_OSX
    self.needsLayout = YES;
#else
    [self setNeedsLayout];
#endif
}

#if TARGET_OS_OSX
- (BOOL)isFlipped {
    return YES;
}

- (void)layout {
    [super layout];
    [self performLayoutPass];
}
#else
- (void)layoutSubviews {
    [super layoutSubviews];
    [self performLayoutPass];
}
#endif

- (void)performLayoutPass {
    CGFloat width = self.bounds.size.width;

    if (!_document || width <= 0) {
        _textLayout = nil;
        _layoutValid = NO;
        [self removeAllLayers];
        [self removeHitViews];
        return;
    }

    if (!_layoutValid || _textLayout.container.width != width) {
        _textLayout = [self layoutForWidth:width];
        _layoutValid = YES;
        _generation += 1;
        _snapshot = nil;
        [self updateHitViews];

        CGSize size = CGSizeMake(std::ceil(_textLayout.size.width), std::ceil(_textLayout.size.height));

        if (!CGSizeEqualToSize(size, _reportedSize)) {
            _reportedSize = size;
            [self invalidateIntrinsicContentSize];

            if (_contentSizeDidChangeHandler) {
                _contentSizeDidChangeHandler();
            }
        }
    }

    [self updateRendering];
}

#pragma mark - Rendering

- (CGFloat)renderScale {
#if TARGET_OS_OSX
    CGFloat scale = self.window.backingScaleFactor ?: NSScreen.mainScreen.backingScaleFactor;
#else
    CGFloat scale = self.traitCollection.displayScale;
#endif
    return scale > 0 ? scale : 2;
}

- (ATRRenderSnapshot *)currentSnapshot {
    if (!_snapshot) {
#if TARGET_OS_OSX
        ATRPlatformAppearance *appearance = self.effectiveAppearance;
#else
        ATRPlatformAppearance *appearance = self.traitCollection;
#endif
        _snapshot = [[ATRRenderSnapshot alloc] initWithLayout:_textLayout
                                                   appearance:appearance
                                                       images:[_images copy]
                                  gradientsIncludeColorGlyphs:_appliesGradientToColorGlyphs];
    }

    return _snapshot;
}

- (void)updateRendering {
    if (!_layoutValid) {
        return;
    }

    CGFloat scale = [self renderScale];

    if (scale != _renderedScale) {
        _renderedScale = scale;
        _generation += 1;
    }

    if (_viewportRenderingEnabled) {
        [_contentLayer removeFromSuperlayer];
        _contentLayer = nil;
        [self updateTiles];
    } else {
        [self removeTiles];
        [self updateContentLayer];
    }
}

- (CALayer *)makeLayer {
    CALayer *layer = [CALayer layer];
    layer.actions = disabledActions();
    [self.layer addSublayer:layer];

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

- (void)updateContentLayer {
    CGRect rect = self.bounds;

    if (!_contentLayer) {
        _contentLayer = [self makeLayer];
    }

    if (_contentGeneration == _generation && CGRectEqualToRect(_contentRect, rect)) {
        return;
    }

    _contentGeneration = _generation;
    _contentRect = rect;
    [self renderRect:rect intoLayer:_contentLayer];
}

- (CGRect)visibleRegion {
    ATRPlatformView *scrollView = _observedScrollView;
    CGRect region = CGRectNull;

    if (scrollView) {
#if TARGET_OS_OSX
        NSClipView *clipView = ((NSScrollView *)scrollView).contentView;
        region = [self convertRect:clipView.bounds fromView:clipView];
#else
        region = [self convertRect:scrollView.bounds fromView:scrollView];
#endif
    } else if (self.window) {
#if TARGET_OS_OSX
        region = self.visibleRect;
#else
        region = [self convertRect:self.window.bounds fromView:nil];
#endif
    }

    if (CGRectIsNull(region)) {
        return CGRectNull;
    }

    return CGRectIntersection(region, self.bounds);
}

- (void)updateTiles {
    CGRect bounds = self.bounds;
    CGFloat tileHeight = _tileHeight;
    NSUInteger tileCount = static_cast<NSUInteger>(std::ceil(CGRectGetHeight(bounds) / tileHeight));
    CGRect visible = [self visibleRegion];
    NSInteger firstNeeded = 0;
    NSInteger lastNeeded = -1;

    if (!CGRectIsNull(visible) && !CGRectIsEmpty(visible) && tileCount > 0) {
        // One tile of lookahead in each direction.
        firstNeeded = std::max<NSInteger>(0, std::floor(CGRectGetMinY(visible) / tileHeight) - 1);
        lastNeeded = std::min<NSInteger>(
            tileCount - 1,
            std::ceil(CGRectGetMaxY(visible) / tileHeight)
        );
    }

    // Tiles stay a little longer than they are prefetched, so scrolling
    // back and forth doesn't redraw them.
    for (NSNumber *key in _tiles.allKeys) {
        NSInteger index = key.integerValue;

        if (index < firstNeeded - 1 || index > lastNeeded + 1 || index >= static_cast<NSInteger>(tileCount)) {
            [_tiles[key] removeFromSuperlayer];
            [_tiles removeObjectForKey:key];
            _tileGenerations.erase(index);
        }
    }

    for (NSInteger index = firstNeeded; index <= lastNeeded; ++index) {
        CGFloat top = index * tileHeight;
        CGRect rect = CGRectMake(0, top, CGRectGetWidth(bounds), std::min(tileHeight, CGRectGetHeight(bounds) - top));
        CALayer *layer = _tiles[@(index)];

        if (!layer) {
            layer = [self makeLayer];
            _tiles[@(index)] = layer;
        } else if (_tileGenerations[index] == _generation) {
            continue;
        }

        _tileGenerations[index] = _generation;
        [self renderRect:rect intoLayer:layer];
    }
}

- (void)renderRect:(CGRect)rect intoLayer:(CALayer *)layer {
    CGFloat scale = _renderedScale;
    layer.bounds = CGRectMake(0, 0, CGRectGetWidth(rect), CGRectGetHeight(rect));
    layer.position = CGPointMake(CGRectGetMidX(rect), CGRectGetMidY(rect));
    layer.contentsScale = scale;

    ATRRenderSnapshot *snapshot = [self currentSnapshot];

    if (!_rendersAsynchronously) {
        layer.contents = (__bridge_transfer id)[snapshot newImageForRect:rect scale:scale];
        return;
    }

    uint64_t generation = _generation;
    __weak ATRTextDisplayView *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        CGImageRef image = [snapshot newImageForRect:rect scale:scale];

        dispatch_async(dispatch_get_main_queue(), ^{
            ATRTextDisplayView *view = weakSelf;

            if (view && view->_generation == generation) {
                layer.contents = (__bridge id)image;
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
    [_contentLayer removeFromSuperlayer];
    _contentLayer = nil;
    _contentGeneration = 0;
}

- (NSIndexSet *)renderedTileIndexes {
    NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];

    for (NSNumber *key in _tiles) {
        [indexes addIndex:key.unsignedIntegerValue];
    }

    return indexes;
}

#pragma mark - Appearance and hierarchy

#if TARGET_OS_OSX
- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    [self invalidateContent];
}

- (void)viewDidChangeBackingProperties {
    [super viewDidChangeBackingProperties];
    [self setNeedsLayoutPass];
}

- (void)viewDidMoveToSuperview {
    [super viewDidMoveToSuperview];
    [self updateScrollViewObservation];
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    [self updateScrollViewObservation];
    [self setNeedsLayoutPass];
}
#else
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];

    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [self invalidateContent];
    } else if (self.traitCollection.displayScale != previousTraitCollection.displayScale) {
        [self setNeedsLayoutPass];
    }
}

- (void)didMoveToSuperview {
    [super didMoveToSuperview];
    [self updateScrollViewObservation];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self updateScrollViewObservation];
    [self setNeedsLayoutPass];
}
#endif

#pragma mark - Scroll view observation

- (ATRPlatformView *)findEnclosingScrollView {
#if TARGET_OS_OSX
    return self.enclosingScrollView;
#else
    for (UIView *view = self.superview; view; view = view.superview) {
        if ([view isKindOfClass:UIScrollView.class]) {
            return view;
        }
    }

    return nil;
#endif
}

- (void)updateScrollViewObservation {
    ATRPlatformView *scrollView = _viewportRenderingEnabled ? [self findEnclosingScrollView] : nil;

    if (scrollView == _observedScrollView) {
        return;
    }

    [self stopObservingScrollView];

    if (!scrollView) {
        return;
    }

    _observedScrollView = scrollView;

#if TARGET_OS_OSX
    NSClipView *clipView = ((NSScrollView *)scrollView).contentView;
    clipView.postsBoundsChangedNotifications = YES;
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(scrollViewDidScroll:)
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

- (void)stopObservingScrollView {
#if TARGET_OS_OSX
    [NSNotificationCenter.defaultCenter removeObserver:self
                                                  name:NSViewBoundsDidChangeNotification
                                                object:nil];
#else
    [_scrollViewForRemoval removeObserver:self forKeyPath:@"contentOffset" context:ATRContentOffsetContext];
    _scrollViewForRemoval = nil;
#endif
    _observedScrollView = nil;
}

#if TARGET_OS_OSX
- (void)scrollViewDidScroll:(NSNotification *)notification {
    [self updateRendering];
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

    [self updateRendering];
}
#endif

#pragma mark - Hit views

- (NSArray<ATRHitView *> *)hitViews {
    return _hitViewsBySet.allValues;
}

- (void)removeHitViews {
    for (ATRHitView *hitView in _hitViewsBySet.allValues) {
        [hitView removeFromSuperview];
    }

    [_hitViewsBySet removeAllObjects];
}

// Hit views are keyed by interaction set, which is stable for one document,
// so relayouts only move their regions.
- (void)updateHitViews {
    if (!_layoutValid) {
        return;
    }

    NSMutableDictionary<NSNumber *, NSMutableArray<NSValue *> *> *regionsBySet = [NSMutableDictionary dictionary];

    for (NSUInteger index = 0; index < _textLayout.hitRegionCount; ++index) {
        ATRHitRegion region = [_textLayout hitRegionAtIndex:index];
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
            hitView = [self makeHitViewForSet:key.unsignedIntValue];
            self->_hitViewsBySet[key] = hitView;
            [self addSubview:hitView];
        }

        [hitView setRegions:regions];
    }];
}

- (ATRHitView *)makeHitViewForSet:(uint32_t)interactionSet {
    ATRHitView *hitView = [[ATRHitView alloc] initWithInteractionSet:interactionSet];
    hitView.delegate = self;
    __weak ATRHitView *weakHitView = hitView;
    NSMutableArray<ATRGestureBinding *> *bindings = [NSMutableArray array];

    for (NSNumber *interaction in [_textLayout interactionsInSet:interactionSet]) {
        ATRGesture gesture = [_document gestureForInteraction:interaction.unsignedIntValue];
        id<ATRGestureRecognizerFactory> factory = [_gestureRegistry factoryForKind:gesture.kind];

        if (!factory) {
            continue;
        }

        [bindings addObject:[factory bindingForGesture:gesture
                                           interaction:interaction.unsignedIntValue
                                               handler:^(uint32_t value, CGPoint location) {
                                                   [weakHitView triggerInteraction:value atLocation:location];
                                               }]];
    }

    [_gesturePolicy configureBindings:bindings];
    [hitView installBindings:bindings];
    return hitView;
}

- (void)hitView:(ATRHitView *)hitView didTriggerInteraction:(uint32_t)interaction atLocation:(CGPoint)location {
    if (_interactionHandler) {
        _interactionHandler(interaction, location);
    }
}

@end
