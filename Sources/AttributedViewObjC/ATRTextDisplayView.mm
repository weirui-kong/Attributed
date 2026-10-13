// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#import "ATRTextDisplayView.h"

#import "ATRHitViewManager.h"
#import "ATRRenderSnapshot.h"
#import "ATRScrollObserver.h"
#import "ATRTileController.h"

#include <cmath>

#if !__has_feature(objc_arc)
#error "AttributedViewObjC must be compiled with ARC."
#endif

namespace {

constexpr CGFloat kDefaultTileHeight = 256;

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
    // CGImage is owned by the UIImage; keep the owner alive until retained.
    __attribute__((objc_precise_lifetime)) UIImage *upright =
        [[[UIGraphicsImageRenderer alloc] initWithSize:image.size format:format]
        imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [image drawInRect:CGRectMake(0, 0, image.size.width, image.size.height)];
        }];
    return upright.CGImage ? CGImageRetain(upright.CGImage) : nullptr;
#endif
}

NSString *const kDefaultTruncationToken = @"\u2026";

CGSize ceilSize(CGSize size) {
    return CGSizeMake(std::ceil(size.width), std::ceil(size.height));
}

} // namespace

@interface ATRTextDisplayView () <ATRHitViewDelegate>
@end

// Assembles the pieces of a text view: layout for the current width, a
// render snapshot, the tile controller that draws it, the scroll observer
// that drives tiling, and the hit view manager for gestures.
@implementation ATRTextDisplayView {
    ATRTextLayout *_textLayout;
    ATRTextLayout *_measureLayout;
    // Supplied with the document; kept only until it is installed or an
    // input changes, so a large stale layout is never held.
    ATRTextLayout *_preparedLayout;
    BOOL _layoutValid;
    CGSize _reportedSize;
    // Loaded sizes of adaptive AsyncImages, keyed by attachment ID.
    NSMutableDictionary<NSNumber *, NSValue *> *_contentSizes;
    NSMutableDictionary<NSNumber *, id> *_images;
    ATRRenderSnapshot *_snapshot;
    ATRTileController *_tiles;
    ATRScrollObserver *_scrollObserver;
    ATRHitViewManager *_hitViews;
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
#if TARGET_OS_OSX
    self.wantsLayer = YES;
    self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawNever;
#else
    self.backgroundColor = UIColor.clearColor;
    self.opaque = NO;
#endif

    _images = [NSMutableDictionary dictionary];
    _contentSizes = [NSMutableDictionary dictionary];
    _tiles = [[ATRTileController alloc] initWithHostLayer:self.layer];
    _hitViews = [[ATRHitViewManager alloc] initWithContainerView:self];
    _hitViews.delegate = self;

    __weak ATRTextDisplayView *weakSelf = self;
    _scrollObserver = [[ATRScrollObserver alloc] initWithChangeHandler:^{
        [weakSelf updateRendering];
    }];
}

#pragma mark - Configuration

- (void)setDocument:(ATRDocument *)document {
    [self setDocument:document layout:nil];
}

- (void)setDocument:(ATRDocument *)document layout:(ATRTextLayout *)layout {
    ATRTextLayout *prepared = layout.document == document ? layout : nil;

    if (_document == document) {
        if (prepared) {
            _preparedLayout = prepared;
            [self setNeedsLayoutPass];
        }

        return;
    }

    _document = document;
    [_hitViews removeAll];
    [_images removeAllObjects];
    [_contentSizes removeAllObjects];
    [self invalidateLayout];
    _preparedLayout = prepared;
}

- (void)setMaximumNumberOfLines:(NSUInteger)maximumNumberOfLines {
    if (_maximumNumberOfLines != maximumNumberOfLines) {
        _maximumNumberOfLines = maximumNumberOfLines;
        [self invalidateLayout];
    }
}

- (void)setTruncationToken:(NSString *)truncationToken {
    // Nil means U+2026, so switching between the two keeps the layout.
    BOOL changed = ![(_truncationToken ?: kDefaultTruncationToken)
        isEqualToString:(truncationToken ?: kDefaultTruncationToken)];
    _truncationToken = [truncationToken copy];

    if (changed) {
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
    [_tiles removeAllLayers];
    [self updateScrollViewObservation];
    [self setNeedsLayoutPass];
}

- (CGFloat)tileHeight {
    return _tiles.tileHeight;
}

- (void)setTileHeight:(CGFloat)tileHeight {
    _tiles.tileHeight = tileHeight > 0 ? tileHeight : kDefaultTileHeight;
    [self setNeedsLayoutPass];
}

- (BOOL)rendersAsynchronously {
    return _tiles.rendersAsynchronously;
}

- (void)setRendersAsynchronously:(BOOL)rendersAsynchronously {
    _tiles.rendersAsynchronously = rendersAsynchronously;
}

- (void)setAppliesGradientToColorGlyphs:(BOOL)appliesGradientToColorGlyphs {
    if (_appliesGradientToColorGlyphs != appliesGradientToColorGlyphs) {
        _appliesGradientToColorGlyphs = appliesGradientToColorGlyphs;
        [self invalidateContent];
    }
}

- (ATRGestureRecognizerRegistry *)gestureRegistry {
    return _hitViews.registry;
}

- (void)setGestureRegistry:(ATRGestureRecognizerRegistry *)gestureRegistry {
    _hitViews.registry = gestureRegistry;
    [self rebuildHitViews];
}

- (id<ATRGesturePolicy>)gesturePolicy {
    return _hitViews.policy;
}

- (void)setGesturePolicy:(id<ATRGesturePolicy>)gesturePolicy {
    _hitViews.policy = gesturePolicy;
    [self rebuildHitViews];
}

- (void)setImage:(ATRPlatformImage *)image forAttachment:(uint32_t)attachment {
    if (!_document || attachment >= _document.attachmentCount
        || [_document attachmentDescriptorAtIndex:attachment].kind == ATRAttachmentKindSpacer) {
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

- (ATRTextContainer)containerForWidth:(CGFloat)width {
    return {
        width,
        INFINITY,
        static_cast<uint32_t>(MIN(_maximumNumberOfLines, (NSUInteger)UINT32_MAX)),
        _lineHeightMode,
    };
}

- (ATRTextLayout *)layoutForWidth:(CGFloat)width {
    // The current layout, even if invalidated, lets an image arriving
    // relayout only its own paragraph.
    return [_document layoutWithContainer:[self containerForWidth:width]
                          truncationToken:_truncationToken
                   attachmentContentSizes:_contentSizes
                           previousLayout:_textLayout];
}

// Whether `layout` is what layoutForWidth: would produce right now.
- (BOOL)layout:(ATRTextLayout *)layout matchesWidth:(CGFloat)width {
    if (!layout || layout.document != _document) {
        return NO;
    }

    ATRTextContainer expected = [self containerForWidth:width];
    ATRTextContainer container = layout.container;
    NSString *token = layout.truncationToken ?: kDefaultTruncationToken;

    return container.width == expected.width && container.maxHeight == expected.maxHeight
        && container.maximumNumberOfLines == expected.maximumNumberOfLines
        && container.lineHeightMode == expected.lineHeightMode
        && [token isEqualToString:_truncationToken ?: kDefaultTruncationToken]
        && [layout.attachmentContentSizes isEqualToDictionary:_contentSizes];
}

// A layout already at hand for `width`, without laying out.
- (ATRTextLayout *)existingLayoutForWidth:(CGFloat)width {
    if (_layoutValid && _textLayout.container.width == width) {
        return _textLayout;
    }

    for (ATRTextLayout *candidate in @[ _preparedLayout ?: NSNull.null, _measureLayout ?: NSNull.null ]) {
        if (candidate != (id)NSNull.null && [self layout:candidate matchesWidth:width]) {
            return candidate;
        }
    }

    return nil;
}

- (CGSize)sizeThatFitsWidth:(CGFloat)width {
    if (!_document || !(width > 0)) {
        return CGSizeZero;
    }

    if (ATRTextLayout *existing = [self existingLayoutForWidth:width]) {
        return ceilSize(existing.size);
    }

    _measureLayout = [self layoutForWidth:width];
    return ceilSize(_measureLayout.size);
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
    _preparedLayout = nil;
    [self notifyContentSizeChange];
    [self setNeedsLayoutPass];
}

- (void)invalidateContent {
    _snapshot = nil;
    [_tiles invalidateContent];
    [self setNeedsLayoutPass];
}

- (void)notifyContentSizeChange {
    [self invalidateIntrinsicContentSize];

    if (_contentSizeDidChangeHandler) {
        _contentSizeDidChangeHandler();
    }
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
        [_tiles removeAllLayers];
        [_hitViews removeAll];
        return;
    }

    if (!_layoutValid || _textLayout.container.width != width) {
        // Applying a layout is always synchronous, so the view never shows
        // or reports a layout for other inputs. Laying out ahead of time
        // belongs to the caller, through setDocument:layout:.
        ATRTextLayout *existing = [self existingLayoutForWidth:width];
        [self installLayout:existing ?: [self layoutForWidth:width]];
    }

    [self updateRendering];
}

- (void)installLayout:(ATRTextLayout *)layout {
    _textLayout = layout;
    _preparedLayout = nil;
    _layoutValid = YES;
    _snapshot = nil;
    [_tiles invalidateContent];
    [_hitViews updateWithLayout:layout visibleRect:[self hitViewRect]];

    CGSize size = ceilSize(layout.size);

    if (!CGSizeEqualToSize(size, _reportedSize)) {
        _reportedSize = size;
        [self notifyContentSizeChange];
    }
}

- (void)rebuildHitViews {
    [_hitViews removeAll];

    if (_layoutValid) {
        [_hitViews updateWithLayout:_textLayout visibleRect:[self hitViewRect]];
    }
}

// Where hit views are kept: everywhere without viewport rendering, else the
// visible region plus one tile above and below, like drawn tiles.
- (CGRect)hitViewRect {
    if (!_viewportRenderingEnabled) {
        return CGRectInfinite;
    }

    CGRect visible = [_scrollObserver visibleRegionOfView:self];
    return CGRectIsNull(visible) ? CGRectNull : CGRectInset(visible, 0, -_tiles.tileHeight);
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

    __weak ATRTextDisplayView *weakSelf = self;
    ATRSnapshotProvider snapshot = ^ATRRenderSnapshot * {
        return [weakSelf currentSnapshot];
    };

    [_hitViews updateVisibleRect:[self hitViewRect]];

    if (_viewportRenderingEnabled) {
        [_tiles renderTilesInBounds:self.bounds
                      visibleRegion:[_scrollObserver visibleRegionOfView:self]
                              scale:[self renderScale]
                           snapshot:snapshot];
    } else {
        [_tiles renderSurfaceInBounds:self.bounds scale:[self renderScale] snapshot:snapshot];
    }
}

- (NSIndexSet *)renderedTileIndexes {
    return _tiles.renderedTileIndexes;
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

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self updateScrollViewObservation];
    [self setNeedsLayoutPass];
}
#endif

// Observation starts and stops only when the view enters or leaves a window,
// plus when viewport rendering is switched while already in one.
- (void)updateScrollViewObservation {
    if (_viewportRenderingEnabled) {
        [_scrollObserver observeFirstScrollViewEnclosing:self];
    } else {
        [_scrollObserver stop];
    }
}

- (ATRPlatformView *)observedScrollView {
    return _scrollObserver.scrollView;
}

#pragma mark - Gestures

- (NSArray<ATRHitView *> *)hitViews {
    return _hitViews.hitViews;
}

- (NSUInteger)reusableHitViewCount {
    return _hitViews.reusableHitViewCount;
}

- (void)hitView:(ATRHitView *)hitView didTriggerInteraction:(uint32_t)interaction atLocation:(CGPoint)location {
    if (_interactionHandler) {
        _interactionHandler(interaction, location);
    }
}

@end
