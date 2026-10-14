// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#import "ATRRenderSnapshot.h"
#import "ATRTypes.h"

// One drawn glyph or attachment, in layout coordinates.
typedef struct ATRGlyphAtom {
    // Atoms with equal `font` and `glyph` draw the same shape, also across
    // documents. Attachments use font 0 and their attachment ID.
    uint32_t font;
    uint32_t glyph;
    // Pen position on the baseline.
    CGPoint origin;
    CGFloat advance;
    // The part of the snapshot's bitmap this atom owns, on its pixel grid.
    // Tiles never overlap; a zero-advance glyph has an empty one.
    CGRect tile;
    // Middle of the font's typographic box relative to the baseline, y down.
    CGFloat midline;
    // At least the font's cap height.
    CGFloat inkHeight;
    // A decimal digit, or a "." or "," next to one.
    BOOL numeric;
} ATRGlyphAtom;

// A layout drawn once into a bitmap, with where each glyph sits in it: what a
// text transition takes apart and animates. Create it on the main thread, like
// the render snapshot it draws.
@interface ATRGlyphSnapshot : NSObject

// Draws over `bounds` plus whatever the layout draws beyond it. A nil
// snapshot gives an empty one: no atoms over a transparent bitmap.
- (nonnull instancetype)initWithRenderSnapshot:(nullable ATRRenderSnapshot *)snapshot
                                        bounds:(CGRect)bounds
                                         scale:(CGFloat)scale NS_DESIGNATED_INITIALIZER;

- (nonnull instancetype)init NS_UNAVAILABLE;
+ (nonnull instancetype)new NS_UNAVAILABLE;

// What the bitmap covers, in layout coordinates, on the pixel grid.
@property (nonatomic, readonly) CGRect frame;
@property (nonatomic, readonly) CGFloat scale;

// Line by line, left to right within a line.
@property (nonatomic, readonly) NSUInteger atomCount;
@property (nonatomic, readonly, nullable) const ATRGlyphAtom *atoms;

// Premultiplied BGRA (bgra8Unorm in Metal), first row on top, sRGB.
@property (nonatomic, readonly) size_t pixelWidth;
@property (nonatomic, readonly) size_t pixelHeight;
@property (nonatomic, readonly) size_t bytesPerRow;
@property (nonatomic, readonly, nullable) const void *pixels;

@end
