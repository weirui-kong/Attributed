// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#import <XCTest/XCTest.h>

#import "ATRDocumentBuilder.h"
#import "ATRRenderSnapshot.h"

#include <vector>

namespace {

struct Pixel {
    uint8_t red;
    uint8_t green;
    uint8_t blue;
    uint8_t alpha;
};

// Decodes an image into unpremultiplied-looking RGBA rows, top row first.
class Bitmap {
public:
    explicit Bitmap(CGImageRef image)
        : width_(CGImageGetWidth(image)),
          height_(CGImageGetHeight(image)),
          pixels_(width_ * height_) {
        CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        CGContextRef context = CGBitmapContextCreate(
            pixels_.data(),
            width_,
            height_,
            8,
            width_ * 4,
            space,
            kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big
        );
        CGContextDrawImage(context, CGRectMake(0, 0, width_, height_), image);
        CGContextRelease(context);
        CGColorSpaceRelease(space);
    }

    size_t width() const { return width_; }
    size_t height() const { return height_; }

    Pixel at(size_t x, size_t y) const { return pixels_[y * width_ + x]; }

    template <typename Predicate> size_t count(Predicate predicate) const {
        size_t result = 0;

        for (const Pixel &pixel : pixels_) {
            result += predicate(pixel) ? 1 : 0;
        }

        return result;
    }

    template <typename Predicate> size_t countInRow(size_t y, Predicate predicate) const {
        size_t result = 0;

        for (size_t x = 0; x < width_; ++x) {
            result += predicate(at(x, y)) ? 1 : 0;
        }

        return result;
    }

private:
    size_t width_;
    size_t height_;
    std::vector<Pixel> pixels_;
};

bool isRed(Pixel pixel) {
    return pixel.alpha > 200 && pixel.red > 200 && pixel.green < 60 && pixel.blue < 60;
}

bool isBlue(Pixel pixel) {
    return pixel.alpha > 200 && pixel.blue > 200 && pixel.red < 60 && pixel.green < 60;
}

bool isGreen(Pixel pixel) {
    return pixel.alpha > 200 && pixel.green > 200 && pixel.red < 60 && pixel.blue < 60;
}

bool isOpaque(Pixel pixel) {
    return pixel.alpha > 200;
}

ATRTextStyle fontStyle(int32_t font) {
    ATRTextStyle style = {};
    style.fields = ATRTextStyleFieldFont;
    style.font = font;
    return style;
}

ATRTextContainer container(double width) {
    return {width, INFINITY, 0, ATRLineHeightModeTypographic};
}

CGImageRef makeTwoToneImage(CGColorRef top, CGColorRef bottom) {
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(
        nullptr,
        20,
        20,
        8,
        0,
        space,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big
    );
    // Bitmap contexts grow upward: the top half is y in 10...20.
    CGContextSetFillColorWithColor(context, top);
    CGContextFillRect(context, CGRectMake(0, 10, 20, 10));
    CGContextSetFillColorWithColor(context, bottom);
    CGContextFillRect(context, CGRectMake(0, 0, 20, 10));
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    CGColorSpaceRelease(space);
    return image;
}

} // namespace

@interface RenderTests : XCTestCase
@end

@implementation RenderTests

- (ATRPlatformFont *)font {
    return [ATRPlatformFont boldSystemFontOfSize:40];
}

- (Bitmap)render:(ATRTextLayout *)layout images:(NSDictionary<NSNumber *, id> *)images {
    ATRRenderSnapshot *snapshot = [[ATRRenderSnapshot alloc] initWithLayout:layout
                                                                 appearance:nil
                                                                     images:images
                                                gradientsIncludeColorGlyphs:NO];
    CGRect rect = CGRectMake(0, 0, layout.container.width, ceil(layout.size.height));
    CGImageRef image = [snapshot newImageForRect:rect scale:1];
    Bitmap bitmap(image);
    CGImageRelease(image);
    return bitmap;
}

- (void)testColorFillAndBackground {
    ATRDocumentBuilder *builder = [[ATRDocumentBuilder alloc] init];
    int32_t font = [builder registerFont:[self font]];
    ATRTextStyle style = fontStyle(font);
    style.fields |= ATRTextStyleFieldForeground | ATRTextStyleFieldBackgroundColor;
    style.foreground = {ATRFillKindColor, [builder registerColor:[ATRPlatformColor redColor]]};
    style.backgroundColor = [builder registerColor:[ATRPlatformColor blueColor]];
    [builder beginParagraph:{} textStyle:style];
    [builder appendText:@"HH"];
    [builder endParagraph];
    ATRTextLayout *layout = [[builder finish] layoutWithContainer:container(200) truncationToken:nil];

    Bitmap bitmap = [self render:layout images:@{}];
    ATRLineInfo line = [layout lineAtIndex:0];
    size_t baselineRow = static_cast<size_t>(line.baseline) - 3;

    XCTAssertGreaterThan(bitmap.count(isRed), 100u);
    XCTAssertGreaterThan(bitmap.count(isBlue), 100u);
    // Glyph pixels sit above the baseline, upright.
    XCTAssertGreaterThan(bitmap.countInRow(baselineRow, isRed), 0u);
    XCTAssertEqual(bitmap.countInRow(static_cast<size_t>(line.baseline) + 3, isRed), 0u);
}

- (void)testGradientFillSpansTheJoinedRect {
    ATRDocumentBuilder *builder = [[ATRDocumentBuilder alloc] init];
    int32_t font = [builder registerFont:[self font]];
    int32_t colors[] = {
        [builder registerColor:[ATRPlatformColor redColor]],
        [builder registerColor:[ATRPlatformColor blueColor]],
    };
    int32_t gradient = [builder registerGradientWithColors:colors
                                                 locations:nil
                                                     count:2
                                                descriptor:{0, 0.5, 1, 0.5, ATRGradientScopeParagraph}];
    ATRTextStyle style = fontStyle(font);
    style.fields |= ATRTextStyleFieldForeground;
    style.foreground = {ATRFillKindGradient, gradient};
    [builder beginParagraph:{} textStyle:fontStyle(font)];
    [builder pushSpan:style interaction:ATRNoInteraction];
    [builder appendText:@"HH"];
    [builder popSpan];
    [builder appendText:@"    "];
    [builder pushSpan:style interaction:ATRNoInteraction];
    [builder appendText:@"HH"];
    [builder popSpan];
    [builder endParagraph];
    ATRTextLayout *layout = [[builder finish] layoutWithContainer:container(400) truncationToken:nil];

    Bitmap bitmap = [self render:layout images:@{}];
    ATRGradientGroupInfo group = [layout gradientGroupAtIndex:0];
    size_t row = static_cast<size_t>([layout lineAtIndex:0].baseline) - 10;
    size_t firstOpaque = SIZE_MAX;
    size_t lastOpaque = 0;

    for (size_t x = 0; x < bitmap.width(); ++x) {
        if (isOpaque(bitmap.at(x, row))) {
            firstOpaque = std::min(firstOpaque, x);
            lastOpaque = x;
        }
    }

    Pixel left = bitmap.at(firstOpaque, row);
    Pixel right = bitmap.at(lastOpaque, row);

    XCTAssertEqual(layout.gradientGroupCount, 1u);
    XCTAssertGreaterThan(left.red, left.blue);
    XCTAssertGreaterThan(right.blue, right.red);
    // No glyph pixels between the two runs, so the gradient is clipped to text.
    XCTAssertEqual(bitmap.at(static_cast<size_t>(CGRectGetMidX(group.rect)), row).alpha, 0);
}

- (void)testUnderlineDecoration {
    ATRDocumentBuilder *builder = [[ATRDocumentBuilder alloc] init];
    int32_t font = [builder registerFont:[self font]];
    ATRTextStyle style = fontStyle(font);
    style.fields |= ATRTextStyleFieldUnderline | ATRTextStyleFieldUnderlineFill;
    style.underline = {ATRUnderlineLinesSingle, ATRUnderlinePatternSolid, 4, ATRUnderlineCornersSquare, 0};
    style.underlineFill = {ATRFillKindColor, [builder registerColor:[ATRPlatformColor greenColor]]};
    [builder beginParagraph:{} textStyle:style];
    [builder appendText:@"Under"];
    [builder endParagraph];
    ATRTextLayout *layout = [[builder finish] layoutWithContainer:container(300) truncationToken:nil];

    Bitmap bitmap = [self render:layout images:@{}];
    ATRDecorationInfo decoration = [layout decorationAtIndex:0];
    size_t row = static_cast<size_t>(CGRectGetMidY(decoration.rect));

    XCTAssertGreaterThan(
        bitmap.countInRow(row, isGreen),
        static_cast<size_t>(CGRectGetWidth(decoration.rect) * 0.9)
    );
}

- (void)testImageAttachmentIsUpright {
    CGColorRef red = CGColorCreateSRGB(1, 0, 0, 1);
    CGColorRef blue = CGColorCreateSRGB(0, 0, 1, 1);
    CGImageRef image = makeTwoToneImage(red, blue);
    ATRDocumentBuilder *builder = [[ATRDocumentBuilder alloc] init];
    ATRAttachmentDescriptor descriptor = {};
    descriptor.sizeKind = ATRAttachmentSizeKindFixed;
    descriptor.width = 20;
    descriptor.height = 20;
    [builder beginParagraph:{} textStyle:{}];
    uint32_t attachment = [builder appendAttachment:descriptor accessibilityLabel:nil];
    [builder endParagraph];
    ATRTextLayout *layout = [[builder finish] layoutWithContainer:container(100) truncationToken:nil];

    Bitmap bitmap = [self render:layout images:@{@(attachment): (__bridge id)image}];
    CGRect frame = [layout attachmentFrameAtIndex:0].frame;

    XCTAssertTrue(isRed(bitmap.at(CGRectGetMidX(frame), CGRectGetMinY(frame) + 3)));
    XCTAssertTrue(isBlue(bitmap.at(CGRectGetMidX(frame), CGRectGetMaxY(frame) - 3)));

    CGImageRelease(image);
    CGColorRelease(red);
    CGColorRelease(blue);
}

- (void)testTileRendersItsOwnSlice {
    ATRDocumentBuilder *builder = [[ATRDocumentBuilder alloc] init];
    int32_t font = [builder registerFont:[self font]];
    ATRTextStyle style = fontStyle(font);
    style.fields |= ATRTextStyleFieldForeground;
    style.foreground = {ATRFillKindColor, [builder registerColor:[ATRPlatformColor redColor]]};
    [builder beginParagraph:{} textStyle:style];
    [builder appendText:@"First"];
    [builder endParagraph];
    [builder beginParagraph:{} textStyle:style];
    [builder appendText:@"Second"];
    [builder endParagraph];
    ATRTextLayout *layout = [[builder finish] layoutWithContainer:container(300) truncationToken:nil];
    ATRRenderSnapshot *snapshot = [[ATRRenderSnapshot alloc] initWithLayout:layout
                                                                 appearance:nil
                                                                     images:@{}
                                                gradientsIncludeColorGlyphs:NO];
    ATRLineInfo second = [layout lineAtIndex:1];
    CGRect tile = CGRectMake(0, CGRectGetMinY(second.frame), 300, CGRectGetHeight(second.frame));

    CGImageRef image = [snapshot newImageForRect:tile scale:2];
    Bitmap bitmap(image);
    CGImageRelease(image);

    XCTAssertEqual(bitmap.height(), static_cast<size_t>(ceil(CGRectGetHeight(tile) * 2)));
    XCTAssertGreaterThan(bitmap.count(isRed), 100u);
    size_t baselineRow = static_cast<size_t>((second.baseline - CGRectGetMinY(tile)) * 2) - 6;
    XCTAssertGreaterThan(bitmap.countInRow(baselineRow, isRed), 0u);
}

- (void)testHitRegionsCoverInteractiveRuns {
    ATRDocumentBuilder *builder = [[ATRDocumentBuilder alloc] init];
    int32_t font = [builder registerFont:[self font]];
    uint32_t tap = [builder registerInteractionWithGesture:{ATRGestureKindTap, 1, 0}];
    [builder beginParagraph:{} textStyle:fontStyle(font)];
    [builder appendText:@"plain "];
    [builder pushSpan:{} interaction:tap];
    [builder appendText:@"ta"];
    [builder pushSpan:fontStyle(font) interaction:ATRNoInteraction];
    [builder appendText:@"p"];
    [builder popSpan];
    [builder popSpan];
    [builder endParagraph];
    ATRDocument *document = [builder finish];
    ATRTextLayout *layout = [document layoutWithContainer:container(400) truncationToken:nil];
    ATRLineInfo line = [layout lineAtIndex:0];

    // "ta" and "p" have different styles but one interaction set, so they
    // merge into one region that ends where the line ends.
    XCTAssertEqual(layout.hitRegionCount, 1u);
    ATRHitRegion region = [layout hitRegionAtIndex:0];
    XCTAssertEqualObjects([layout interactionsInSet:region.interactionSet], @[@(tap)]);
    XCTAssertEqualWithAccuracy(CGRectGetMaxX(region.rect), CGRectGetMaxX(line.frame), 0.5);
    XCTAssertGreaterThan(CGRectGetMinX(region.rect), CGRectGetMinX(line.frame));
    XCTAssertEqualWithAccuracy(CGRectGetHeight(region.rect), CGRectGetHeight(line.frame), 0.001);
    XCTAssertEqual([layout rectsForInteraction:tap].count, 1u);
    XCTAssertTrue(NSEqualRanges([document rangeForInteraction:tap], NSMakeRange(6, 3)));
    XCTAssertEqualObjects([document textInRange:NSMakeRange(6, 3)], @"tap");
}

@end
