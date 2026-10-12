// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#import "ATRTextLayout.h"
#import "ATRTypes.h"

// Everything needed to draw a layout for one appearance. Create it on the
// main thread, where dynamic colors are resolved; drawing is then safe on
// any thread.
@interface ATRRenderSnapshot : NSObject

@property (nonatomic, readonly, nonnull) ATRTextLayout *layout;

// `appearance` is a trait collection on iOS and an NSAppearance on macOS;
// nil uses the current one. `images` maps attachment IDs to CGImages.
- (nonnull instancetype)initWithLayout:(nonnull ATRTextLayout *)layout
                            appearance:(nullable ATRPlatformAppearance *)appearance
                                images:(nonnull NSDictionary<NSNumber *, id> *)images
           gradientsIncludeColorGlyphs:(BOOL)gradientsIncludeColorGlyphs NS_DESIGNATED_INITIALIZER;

- (nonnull instancetype)init NS_UNAVAILABLE;
+ (nonnull instancetype)new NS_UNAVAILABLE;

// `context` must use layout coordinates: top-left origin, y downward.
- (void)drawInContext:(nonnull CGContextRef)context rect:(CGRect)rect;

// Renders `rect` of the layout into a new bitmap at `scale` pixels per
// point. Returns NULL for an empty rect.
- (nullable CGImageRef)newImageForRect:(CGRect)rect scale:(CGFloat)scale CF_RETURNS_RETAINED;

@end
