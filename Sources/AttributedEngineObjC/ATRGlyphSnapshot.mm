// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#import "ATRGlyphSnapshot.h"

#import "ATRDocument+Internal.h"
#import "ATRTextLayout+Internal.h"

#include <cmath>
#include <vector>

#include "atr/layout/GlyphAtoms.hpp"

#if !__has_feature(objc_arc)
#error "AttributedEngineObjC must be compiled with ARC."
#endif

@implementation ATRGlyphSnapshot {
    std::vector<ATRGlyphAtom> _atoms;
    atr::CFRef<CGContextRef> _context;
}

- (instancetype)initWithRenderSnapshot:(ATRRenderSnapshot *)snapshot bounds:(CGRect)bounds scale:(CGFloat)scale {
    self = [super init];

    if (!self) {
        return nil;
    }

    _scale = scale > 0 ? scale : 1;
    CGRect extent = bounds;

    if (snapshot) {
        ATRTextLayout *layout = snapshot.layout;

        for (const atr::GlyphAtom &atom : atr::glyphAtoms(layout.engineLayout, layout.document.resolvedDocument, _scale)) {
            CGRect tile = CGRectMake(atom.tile.x, atom.tile.y, atom.tile.width, atom.tile.height);
            _atoms.push_back({
                atom.font,
                atom.glyph,
                CGPointMake(atom.x, atom.baseline),
                atom.advance,
                tile,
                atom.midline,
                atom.inkHeight,
                atom.numeric,
            });

            if (!CGRectIsEmpty(tile)) {
                extent = CGRectUnion(extent, tile);
            }
        }
    }

    CGFloat minX = std::floor(CGRectGetMinX(extent) * _scale) / _scale;
    CGFloat minY = std::floor(CGRectGetMinY(extent) * _scale) / _scale;
    _pixelWidth = static_cast<size_t>(std::max<CGFloat>(1, std::ceil((CGRectGetMaxX(extent) - minX) * _scale)));
    _pixelHeight = static_cast<size_t>(std::max<CGFloat>(1, std::ceil((CGRectGetMaxY(extent) - minY) * _scale)));
    _frame = CGRectMake(minX, minY, _pixelWidth / _scale, _pixelHeight / _scale);

    auto colorSpace = atr::CFRef<CGColorSpaceRef>::adopt(CGColorSpaceCreateWithName(kCGColorSpaceSRGB));
    _context = atr::CFRef<CGContextRef>::adopt(CGBitmapContextCreate(
        nullptr,
        _pixelWidth,
        _pixelHeight,
        8,
        0,
        colorSpace.get(),
        static_cast<uint32_t>(kCGImageAlphaPremultipliedFirst) | kCGBitmapByteOrder32Little
    ));

    if (_context && snapshot) {
        CGContextRef context = _context.get();
        CGContextTranslateCTM(context, 0, _pixelHeight);
        CGContextScaleCTM(context, _scale, -_scale);
        CGContextTranslateCTM(context, -minX, -minY);
        [snapshot drawInContext:context rect:_frame];
    }

    _bytesPerRow = _context ? CGBitmapContextGetBytesPerRow(_context.get()) : 0;
    return self;
}

- (NSUInteger)atomCount {
    return _atoms.size();
}

- (const ATRGlyphAtom *)atoms {
    return _atoms.empty() ? nullptr : _atoms.data();
}

- (const void *)pixels {
    return _context ? CGBitmapContextGetData(_context.get()) : nullptr;
}

@end
