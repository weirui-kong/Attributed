// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#import "ATRDocument.h"
#import "ATRGestures.h"
#import "ATRHitView.h"
#import "ATRTextLayout.h"
#import "ATRTypes.h"

// The display surface behind the public Swift text view. It lays out its
// document for its own width, draws into layer bitmaps (optionally off the
// main thread), splits drawing into tiles when viewport rendering is on, and
// manages the hit views that recognize gestures on interactive text.
@interface ATRTextDisplayView : ATRPlatformView

@property (nonatomic, strong, nullable) ATRDocument *document;
// Sets the document with a layout made ahead of time, for example on a
// background queue. The layout is used whenever it matches the view's width
// and settings; otherwise the view lays out again. A layout of another
// document is ignored.
- (void)setDocument:(nullable ATRDocument *)document layout:(nullable ATRTextLayout *)layout;
// Zero means unlimited.
@property (nonatomic) NSUInteger maximumNumberOfLines;
// Nil uses U+2026.
@property (nonatomic, copy, nullable) NSString *truncationToken;
@property (nonatomic) ATRLineHeightMode lineHeightMode;

// Off by default. When on, drawing is split into horizontal tiles of
// `tileHeight` points, and only tiles near the visible part of the first
// enclosing scroll view are kept; the view observes that scroll view's
// position while it is in a window. Hit views follow the same region and
// are reused as interactive text scrolls in and out.
@property (nonatomic, getter=isViewportRenderingEnabled) BOOL viewportRenderingEnabled;
// 256 by default.
@property (nonatomic) CGFloat tileHeight;
// Off by default: color glyphs such as emoji keep their own colors.
@property (nonatomic) BOOL appliesGradientToColorGlyphs;
// Off by default. When on, bitmaps are drawn on a background queue and
// installed on the main thread. A tile that scrolls into view stays blank
// until its bitmap is ready, so fast scrolling can briefly show blank areas.
@property (nonatomic) BOOL rendersAsynchronously;

// Interactive text gets one ATRHitView per interaction set; the hit views
// host the gesture recognizers and this view manages them. Defaults to
// +[ATRGestureRecognizerRegistry defaultRegistry] and ATRDefaultGesturePolicy;
// replacing either rebuilds the hit views.
@property (nonatomic, strong, nonnull) ATRGestureRecognizerRegistry *gestureRegistry;
@property (nonatomic, strong, nonnull) id<ATRGesturePolicy> gesturePolicy;

// Receives the ID of an interaction whose gesture was recognized, and where,
// in this view's coordinates.
@property (nonatomic, copy, nullable) void (^interactionHandler)(uint32_t interaction, CGPoint location);
// Called after the measured size changes, for example so an enclosing view
// can invalidate its intrinsic content size.
@property (nonatomic, copy, nullable) void (^contentSizeDidChangeHandler)(void);

// The layout for the current width, or nil before the first layout pass.
@property (nonatomic, readonly, nullable) ATRTextLayout *textLayout;

// Installs an attachment's image. An adaptive AsyncImage relays out with the
// image's size; other attachments only redraw. Nil removes the image.
- (void)setImage:(nullable ATRPlatformImage *)image forAttachment:(uint32_t)attachment;

// The rounded-up layout size for `width`.
- (CGSize)sizeThatFitsWidth:(CGFloat)width;

// Diagnostics.
@property (nonatomic, readonly, nonnull) NSIndexSet *renderedTileIndexes;
// The visible hit views, and the hidden ones waiting for reuse.
@property (nonatomic, readonly, nonnull) NSArray<ATRHitView *> *hitViews;
@property (nonatomic, readonly) NSUInteger reusableHitViewCount;
@property (nonatomic, readonly, nullable) ATRPlatformView *observedScrollView;

@end
