// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#import <CoreText/CoreText.h>
#import <XCTest/XCTest.h>

#import "ATRDocumentBuilder.h"

namespace {

constexpr double kTolerance = 0.5;

ATRTextContainer container(double width) {
    return {width, INFINITY, 0, ATRLineHeightModeTypographic};
}

ATRTextStyle fontStyle(int32_t font) {
    ATRTextStyle style = {};
    style.fields = ATRTextStyleFieldFont;
    style.font = font;
    return style;
}

ATRParagraphStyle alignment(ATRTextAlignment value) {
    ATRParagraphStyle style = {};
    style.fields = ATRParagraphStyleFieldAlignment;
    style.alignment = value;
    return style;
}

ATRAttachmentDescriptor fixedAttachment(double width, double height) {
    ATRAttachmentDescriptor descriptor = {};
    descriptor.sizeKind = ATRAttachmentSizeKindFixed;
    descriptor.width = width;
    descriptor.height = height;
    return descriptor;
}

ATRAttachmentDescriptor adaptiveAttachment(double maxWidth, double contentWidth, double contentHeight) {
    ATRAttachmentDescriptor descriptor = {};
    descriptor.sizeKind = ATRAttachmentSizeKindAdaptive;
    descriptor.fields = ATRAttachmentFieldMaxWidth;
    descriptor.maxWidth = maxWidth;

    if (contentWidth > 0) {
        descriptor.fields |= ATRAttachmentFieldContentSize;
        descriptor.contentWidth = contentWidth;
        descriptor.contentHeight = contentHeight;
    }

    return descriptor;
}

NSString *const kLongText =
    @"The quick brown fox jumps over the lazy dog and keeps running across the field.";

} // namespace

@interface LayoutTests : XCTestCase
@end

@implementation LayoutTests

- (ATRDocument *)documentWithParagraphs:(NSArray<NSString *> *)paragraphs
                         paragraphStyle:(ATRParagraphStyle)paragraphStyle {
    ATRDocumentBuilder *builder = [[ATRDocumentBuilder alloc] init];
    int32_t font = [builder registerFont:[self font]];

    for (NSString *text in paragraphs) {
        [builder beginParagraph:paragraphStyle textStyle:fontStyle(font)];
        [builder appendText:text];
        [builder endParagraph];
    }

    return [builder finish];
}

- (ATRPlatformFont *)font {
    return [ATRPlatformFont systemFontOfSize:16];
}

- (void)testLinesWrapWithinWidthAndStack {
    ATRTextLayout *layout = [[self documentWithParagraphs:@[kLongText] paragraphStyle:{}]
        layoutWithContainer:container(120)
            truncationToken:nil];

    XCTAssertGreaterThan(layout.lineCount, 2u);
    double previousBottom = 0;

    for (NSUInteger index = 0; index < layout.lineCount; ++index) {
        ATRLineInfo line = [layout lineAtIndex:index];
        XCTAssertLessThanOrEqual(CGRectGetMaxX(line.frame), 120 + kTolerance);
        XCTAssertEqualWithAccuracy(CGRectGetMinY(line.frame), previousBottom, 0.001);
        previousBottom = CGRectGetMaxY(line.frame);
    }

    XCTAssertEqualWithAccuracy(layout.size.height, previousBottom, 0.001);
    XCTAssertLessThanOrEqual(layout.size.width, 120);
    XCTAssertFalse(layout.truncated);
}

- (void)testLineAndParagraphSpacing {
    ATRParagraphStyle spacing = {};
    spacing.fields = ATRParagraphStyleFieldLineSpacing | ATRParagraphStyleFieldParagraphSpacing;
    spacing.lineSpacing = 5;
    spacing.paragraphSpacing = 20;
    ATRTextLayout *layout = [[self documentWithParagraphs:@[kLongText, @"Second"]
                                           paragraphStyle:spacing]
        layoutWithContainer:container(200)
            truncationToken:nil];

    NSUInteger last = layout.lineCount - 1;
    ATRLineInfo first = [layout lineAtIndex:0];
    ATRLineInfo second = [layout lineAtIndex:1];
    ATRLineInfo lastOfFirst = [layout lineAtIndex:last - 1];
    ATRLineInfo nextParagraph = [layout lineAtIndex:last];

    XCTAssertEqual(second.paragraph, 0u);
    XCTAssertEqualWithAccuracy(CGRectGetMinY(second.frame) - CGRectGetMaxY(first.frame), 5, 0.001);
    XCTAssertEqual(nextParagraph.paragraph, 1u);
    XCTAssertEqualWithAccuracy(
        CGRectGetMinY(nextParagraph.frame) - CGRectGetMaxY(lastOfFirst.frame),
        20,
        0.001
    );
}

- (void)testAlignmentAndNaturalRightToLeft {
    ATRTextLayout *right = [[self documentWithParagraphs:@[@"Right"]
                                          paragraphStyle:alignment(ATRTextAlignmentRight)]
        layoutWithContainer:container(300)
            truncationToken:nil];
    ATRTextLayout *center = [[self documentWithParagraphs:@[@"Center"]
                                           paragraphStyle:alignment(ATRTextAlignmentCenter)]
        layoutWithContainer:container(300)
            truncationToken:nil];
    ATRTextLayout *hebrew = [[self documentWithParagraphs:@[@"שלום"] paragraphStyle:{}]
        layoutWithContainer:container(300)
            truncationToken:nil];

    ATRLineInfo rightLine = [right lineAtIndex:0];
    ATRLineInfo centerLine = [center lineAtIndex:0];
    ATRLineInfo hebrewLine = [hebrew lineAtIndex:0];

    XCTAssertEqualWithAccuracy(CGRectGetMaxX(rightLine.frame), 300, kTolerance);
    XCTAssertEqualWithAccuracy(
        CGRectGetMinX(centerLine.frame),
        (300 - CGRectGetWidth(centerLine.frame)) / 2,
        kTolerance
    );
    XCTAssertEqualWithAccuracy(CGRectGetMaxX(hebrewLine.frame), 300, kTolerance);
}

- (void)testAttachmentSizing {
    ATRDocumentBuilder *builder = [[ATRDocumentBuilder alloc] init];
    [builder beginParagraph:{} textStyle:{}];
    [builder appendText:@"A"];
    [builder appendAttachment:fixedAttachment(16, 12) accessibilityLabel:nil];
    [builder appendAttachment:adaptiveAttachment(80, 200, 100) accessibilityLabel:nil];
    [builder appendAttachment:adaptiveAttachment(500, 200, 100) accessibilityLabel:nil];
    [builder appendAttachment:adaptiveAttachment(80, 0, 0) accessibilityLabel:nil];
    [builder endParagraph];
    ATRTextLayout *layout = [[builder finish] layoutWithContainer:container(150) truncationToken:nil];

    XCTAssertEqual(layout.attachmentFrameCount, 4u);
    NSMutableDictionary<NSNumber *, NSValue *> *sizes = [NSMutableDictionary dictionary];

    for (NSUInteger index = 0; index < layout.attachmentFrameCount; ++index) {
        ATRAttachmentFrame frame = [layout attachmentFrameAtIndex:index];
        sizes[@(frame.attachment)] = [NSValue valueWithBytes:&frame.frame objCType:@encode(CGRect)];
    }

    auto size = [&](uint32_t attachment) {
        CGRect rect = CGRectZero;
        [sizes[@(attachment)] getValue:&rect];
        return rect.size;
    };

    XCTAssertTrue(CGSizeEqualToSize(size(0), CGSizeMake(16, 12)));
    XCTAssertTrue(CGSizeEqualToSize(size(1), CGSizeMake(80, 40)));
    XCTAssertTrue(CGSizeEqualToSize(size(2), CGSizeMake(150, 75)));
    XCTAssertTrue(CGSizeEqualToSize(size(3), CGSizeZero));
}

- (void)testUnsizedAsyncImageTakesAdjacentCharacterHeight {
    ATRPlatformFont *small = [ATRPlatformFont systemFontOfSize:16];
    ATRPlatformFont *large = [ATRPlatformFont systemFontOfSize:30];
#if TARGET_OS_OSX
    ATRPlatformFont *defaultFont = [NSFont systemFontOfSize:NSFont.systemFontSize];
#else
    ATRPlatformFont *defaultFont = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
#endif
    ATRAttachmentDescriptor unsized = adaptiveAttachment(80, 0, 0);
    unsized.pipeline = ATRImagePipelineAsyncImage;

    ATRDocumentBuilder *builder = [[ATRDocumentBuilder alloc] init];
    int32_t smallFont = [builder registerFont:small];
    int32_t largeFont = [builder registerFont:large];
    [builder beginParagraph:{} textStyle:fontStyle(smallFont)];
    [builder appendText:@"A"];
    uint32_t afterText = [builder appendAttachment:unsized accessibilityLabel:nil];
    uint32_t beforeText = [builder appendAttachment:unsized accessibilityLabel:nil];
    [builder pushSpan:fontStyle(largeFont) interaction:ATRNoInteraction];
    [builder appendText:@"B"];
    [builder popSpan];
    [builder endParagraph];
    [builder beginParagraph:{} textStyle:{}];
    uint32_t alone = [builder appendAttachment:unsized accessibilityLabel:nil];
    [builder endParagraph];
    ATRTextLayout *layout = [[builder finish] layoutWithContainer:container(300) truncationToken:nil];

    auto frameOf = [&](uint32_t attachment) {
        for (NSUInteger index = 0; index < layout.attachmentFrameCount; ++index) {
            ATRAttachmentFrame frame = [layout attachmentFrameAtIndex:index];

            if (frame.attachment == attachment) {
                return frame;
            }
        }

        return ATRAttachmentFrame{};
    };
    auto height = [](ATRPlatformFont *font) {
        CTFontRef ctFont = (__bridge CTFontRef)font;
        return CTFontGetAscent(ctFont) + CTFontGetDescent(ctFont);
    };

    ATRAttachmentFrame previous = frameOf(afterText);
    ATRAttachmentFrame next = frameOf(beforeText);
    ATRAttachmentFrame fallback = frameOf(alone);
    ATRLineInfo firstLine = [layout lineAtIndex:0];

    XCTAssertEqual(CGRectGetWidth(previous.frame), 0);
    XCTAssertEqualWithAccuracy(CGRectGetHeight(previous.frame), height(small), 0.001);
    XCTAssertEqualWithAccuracy(
        CGRectGetMinY(previous.frame),
        firstLine.baseline - CTFontGetAscent((__bridge CTFontRef)small),
        0.001
    );
    XCTAssertEqualWithAccuracy(CGRectGetHeight(next.frame), height(large), 0.001);
    XCTAssertEqualWithAccuracy(CGRectGetHeight(fallback.frame), height(defaultFont), 0.001);
    XCTAssertGreaterThan(CGRectGetHeight([layout lineAtIndex:1].frame), 0);
}

- (void)testMaximumLinesTruncatesLastLine {
    ATRTextContainer limited = container(120);
    limited.maximumNumberOfLines = 2;
    ATRTextLayout *layout = [[self documentWithParagraphs:@[kLongText] paragraphStyle:{}]
        layoutWithContainer:limited
            truncationToken:nil];

    XCTAssertEqual(layout.lineCount, 2u);
    XCTAssertTrue(layout.truncated);
    XCTAssertTrue([layout lineAtIndex:1].truncated);
    XCTAssertLessThanOrEqual(CGRectGetMaxX([layout lineAtIndex:1].frame), 120 + kTolerance);
}

- (void)testCutAtParagraphBoundaryStillTruncates {
    ATRTextContainer limited = container(300);
    limited.maximumNumberOfLines = 1;
    ATRTextLayout *layout = [[self documentWithParagraphs:@[@"First", @"Second"] paragraphStyle:{}]
        layoutWithContainer:limited
            truncationToken:@"..."];

    XCTAssertEqual(layout.lineCount, 1u);
    XCTAssertTrue(layout.truncated);
    ATRLineInfo line = [layout lineAtIndex:0];
    XCTAssertTrue(line.truncated);

    ATRTextLayout *untruncated = [[self documentWithParagraphs:@[@"First"] paragraphStyle:{}]
        layoutWithContainer:container(300)
            truncationToken:nil];
    XCTAssertGreaterThan(CGRectGetWidth(line.frame), CGRectGetWidth([untruncated lineAtIndex:0].frame));
}

- (void)testMaximumHeightSmallerThanOneLine {
    ATRTextContainer limited = container(300);
    limited.maxHeight = 1;
    ATRTextLayout *layout = [[self documentWithParagraphs:@[@"Text"] paragraphStyle:{}]
        layoutWithContainer:limited
            truncationToken:nil];

    XCTAssertEqual(layout.lineCount, 0u);
    XCTAssertTrue(layout.truncated);
    XCTAssertTrue(CGSizeEqualToSize(layout.size, CGSizeZero));
}

- (void)testGradientGroupsFollowScope {
    ATRDocumentBuilder *builder = [[ATRDocumentBuilder alloc] init];
    int32_t font = [builder registerFont:[self font]];
    int32_t colors[] = {0, 0};
    int32_t paragraphGradient = [builder registerGradientWithColors:colors
                                                          locations:nil
                                                              count:2
                                                         descriptor:{0, 0.5, 1, 0.5, ATRGradientScopeParagraph}];
    int32_t lineGradient = [builder registerGradientWithColors:colors
                                                     locations:nil
                                                         count:2
                                                    descriptor:{0, 0.5, 1, 0.5, ATRGradientScopeLine}];
    ATRTextStyle paragraphFill = fontStyle(font);
    paragraphFill.fields |= ATRTextStyleFieldForeground;
    paragraphFill.foreground = {ATRFillKindGradient, paragraphGradient};
    ATRTextStyle lineFill = fontStyle(font);
    lineFill.fields |= ATRTextStyleFieldForeground;
    lineFill.foreground = {ATRFillKindGradient, lineGradient};

    [builder beginParagraph:{} textStyle:fontStyle(font)];
    [builder pushSpan:paragraphFill interaction:ATRNoInteraction];
    [builder appendText:@"Warm"];
    [builder popSpan];
    [builder appendText:@" plain "];
    [builder pushSpan:paragraphFill interaction:ATRNoInteraction];
    [builder appendText:@"glow"];
    [builder popSpan];
    [builder endParagraph];

    [builder beginParagraph:{} textStyle:fontStyle(font)];
    [builder pushSpan:lineFill interaction:ATRNoInteraction];
    [builder appendText:kLongText];
    [builder popSpan];
    [builder endParagraph];

    ATRTextLayout *layout = [[builder finish] layoutWithContainer:container(150) truncationToken:nil];
    NSUInteger paragraphGroups = 0;
    NSUInteger lineGroups = 0;

    for (NSUInteger index = 0; index < layout.gradientGroupCount; ++index) {
        ATRGradientGroupInfo group = [layout gradientGroupAtIndex:index];

        if (group.gradient == paragraphGradient) {
            ++paragraphGroups;
            XCTAssertEqual(group.memberCount, 2u);
            ATRLineInfo line = [layout lineAtIndex:0];
            XCTAssertGreaterThan(CGRectGetWidth(group.rect), CGRectGetWidth(line.frame) * 0.8);
        } else {
            ++lineGroups;
            XCTAssertEqual(group.scope, ATRGradientScopeLine);
        }
    }

    XCTAssertEqual(paragraphGroups, 1u);
    XCTAssertEqual(lineGroups, layout.lineCount - 1);
}

- (void)testEqualAdjacentUnderlinesMerge {
    ATRDocumentBuilder *builder = [[ATRDocumentBuilder alloc] init];
    int32_t font = [builder registerFont:[self font]];
    int32_t highlight = [builder registerColor:[ATRPlatformColor yellowColor]];
    ATRTextStyle underlined = fontStyle(font);
    underlined.fields |= ATRTextStyleFieldUnderline;
    underlined.underline = {ATRUnderlineLinesSingle, ATRUnderlinePatternSolid, 0, ATRUnderlineCornersCapsule, 0};
    ATRTextStyle highlighted = underlined;
    highlighted.fields |= ATRTextStyleFieldBackgroundColor;
    highlighted.backgroundColor = highlight;
    ATRTextStyle dashed = underlined;
    dashed.underline.pattern = ATRUnderlinePatternDash;

    [builder beginParagraph:{} textStyle:fontStyle(font)];
    [builder pushSpan:underlined interaction:ATRNoInteraction];
    [builder appendText:@"one"];
    [builder popSpan];
    [builder pushSpan:highlighted interaction:ATRNoInteraction];
    [builder appendText:@"two"];
    [builder popSpan];
    [builder pushSpan:dashed interaction:ATRNoInteraction];
    [builder appendText:@"three"];
    [builder popSpan];
    [builder endParagraph];

    ATRTextLayout *layout = [[builder finish] layoutWithContainer:container(400) truncationToken:nil];

    XCTAssertEqual(layout.decorationCount, 2u);
    ATRDecorationInfo merged = [layout decorationAtIndex:0];
    ATRDecorationInfo separate = [layout decorationAtIndex:1];
    XCTAssertEqualWithAccuracy(CGRectGetMaxX(merged.rect), CGRectGetMinX(separate.rect), kTolerance);
    XCTAssertGreaterThan(CGRectGetMinY(merged.rect), [layout lineAtIndex:0].baseline);
    XCTAssertEqual(merged.gradientGroup, -1);
}

- (void)testGlyphBoundsModeContainsTallGlyphs {
    NSString *myanmar = @"ကျွန်ုပ် ဒီ";
    ATRDocument *document = [self documentWithParagraphs:@[myanmar, myanmar] paragraphStyle:{}];
    ATRTextContainer glyphBounds = container(400);
    glyphBounds.lineHeightMode = ATRLineHeightModeGlyphBounds;

    ATRTextLayout *typographic = [document layoutWithContainer:container(400) truncationToken:nil];
    ATRTextLayout *tall = [document layoutWithContainer:glyphBounds truncationToken:nil];

    for (NSUInteger index = 0; index < tall.lineCount; ++index) {
        ATRLineInfo line = [tall lineAtIndex:index];
        XCTAssertGreaterThanOrEqual(line.drawnTop, CGRectGetMinY(line.frame) - 0.001);
        XCTAssertLessThanOrEqual(line.drawnBottom, CGRectGetMaxY(line.frame) + 0.001);
    }

    // Typographic lines keep the declared font's height, so the stacked
    // Myanmar marks overflow into the next line.
    ATRLineInfo typographicLine = [typographic lineAtIndex:0];
    XCTAssertGreaterThan(typographicLine.drawnBottom, CGRectGetMaxY(typographicLine.frame));
    XCTAssertGreaterThan(tall.size.height, typographic.size.height);
}

@end
