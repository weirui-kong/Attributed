// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#import "ATRRenderSnapshot.h"

#import "ATRDocument+Internal.h"
#import "ATRTextLayout+Internal.h"

#include "atr/render/Render.hpp"

#if !__has_feature(objc_arc)
#error "AttributedEngineObjC must be compiled with ARC."
#endif

namespace {

atr::CFRef<CGColorRef> resolveColor(ATRPlatformColor *color, ATRPlatformAppearance *appearance) {
#if TARGET_OS_OSX
    __block CGColorRef result = nullptr;
    NSAppearance *target = appearance ?: NSApp.effectiveAppearance ?: NSAppearance.currentDrawingAppearance;
    [target performAsCurrentDrawingAppearance:^{
        result = CGColorRetain(color.CGColor);
    }];
    return atr::CFRef<CGColorRef>::adopt(result);
#else
    // CGColor is owned by the UIColor; keep the owner alive until retained.
    __attribute__((objc_precise_lifetime)) UIColor *resolved =
        appearance ? [color resolvedColorWithTraitCollection:appearance] : color;
    return atr::CFRef<CGColorRef>::retain(resolved.CGColor);
#endif
}

} // namespace

@implementation ATRRenderSnapshot {
    atr::RenderResources _resources;
}

- (instancetype)initWithLayout:(ATRTextLayout *)layout
                    appearance:(ATRPlatformAppearance *)appearance
                        images:(NSDictionary<NSNumber *, id> *)images
   gradientsIncludeColorGlyphs:(BOOL)gradientsIncludeColorGlyphs {
    self = [super init];

    if (self) {
        _layout = layout;
        ATRDocument *document = layout.document;

        for (NSUInteger index = 0; index < document.colorCount; ++index) {
            _resources.colors.push_back(resolveColor([document colorAtIndex:index], appearance));
        }

        _resources.images.resize(document.attachmentCount);

        [images enumerateKeysAndObjectsUsingBlock:^(NSNumber *key, id image, BOOL *stop) {
            NSUInteger attachment = key.unsignedIntegerValue;

            if (attachment < self->_resources.images.size()) {
                self->_resources.images[attachment] =
                    atr::CFRef<CGImageRef>::retain((__bridge CGImageRef)image);
            }
        }];

        _resources.gradientsIncludeColorGlyphs = gradientsIncludeColorGlyphs;
    }

    return self;
}

- (void)drawInContext:(CGContextRef)context rect:(CGRect)rect {
    ATRDocument *document = _layout.document;
    atr::render(
        context,
        _layout.engineLayout,
        document.engineDocument,
        document.resolvedDocument,
        _resources,
        {rect.origin.x, rect.origin.y, rect.size.width, rect.size.height}
    );
}

- (CGImageRef)newImageForRect:(CGRect)rect scale:(CGFloat)scale {
    size_t width = static_cast<size_t>(std::ceil(CGRectGetWidth(rect) * scale));
    size_t height = static_cast<size_t>(std::ceil(CGRectGetHeight(rect) * scale));

    if (width == 0 || height == 0) {
        return nullptr;
    }

    auto colorSpace = atr::CFRef<CGColorSpaceRef>::adopt(CGColorSpaceCreateWithName(kCGColorSpaceSRGB));
    auto context = atr::CFRef<CGContextRef>::adopt(CGBitmapContextCreate(
        nullptr,
        width,
        height,
        8,
        0,
        colorSpace.get(),
        kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host
    ));

    if (!context) {
        return nullptr;
    }

    // Bitmap contexts grow upward; flip to layout coordinates and move the
    // requested rect to the origin.
    CGContextTranslateCTM(context.get(), 0, height);
    CGContextScaleCTM(context.get(), scale, -scale);
    CGContextTranslateCTM(context.get(), -CGRectGetMinX(rect), -CGRectGetMinY(rect));
    [self drawInContext:context.get() rect:rect];
    return CGBitmapContextCreateImage(context.get());
}

@end
