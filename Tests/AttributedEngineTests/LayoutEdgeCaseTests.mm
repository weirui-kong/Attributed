// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#import <CoreText/CoreText.h>
#import <XCTest/XCTest.h>

#import "ATRDocumentBuilder.h"

#include <initializer_list>
#include <utility>

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

ATRAttachmentDescriptor adaptiveAttachment(double contentWidth, double contentHeight) {
    ATRAttachmentDescriptor descriptor = {};
    descriptor.sizeKind = ATRAttachmentSizeKindAdaptive;

    if (contentWidth > 0) {
        descriptor.fields |= ATRAttachmentFieldContentSize;
        descriptor.contentWidth = contentWidth;
        descriptor.contentHeight = contentHeight;
    }

    return descriptor;
}

ATRUnderline solidUnderline() {
    return {ATRUnderlineLinesSingle, ATRUnderlinePatternSolid, 0, ATRUnderlineCornersSquare, 0};
}

NSString *const kLongText =
    @"The quick brown fox jumps over the lazy dog and keeps running across the field.";

} // namespace

@interface LayoutEdgeCaseTests : XCTestCase
@end

@implementation LayoutEdgeCaseTests

- (ATRPlatformFont *)font {
    return [ATRPlatformFont systemFontOfSize:16];
}

- (ATRDocument *)documentWithParagraphs:(NSArray<NSString *> *)paragraphs
                         paragraphStyle:(ATRParagraphStyle)paragraphStyle
                              textStyle:(ATRTextStyle)textStyle {
    ATRDocumentBuilder *builder = [[ATRDocumentBuilder alloc] init];
    int32_t font = [builder registerFont:[self font]];
    ATRTextStyle style = textStyle;

    if (!(style.fields & ATRTextStyleFieldFont)) {
        style.fields |= ATRTextStyleFieldFont;
        style.font = font;
    }

    for (NSString *text in paragraphs) {
        [builder beginParagraph:paragraphStyle textStyle:style];
        [builder appendText:text];
        [builder endParagraph];
    }

    return [builder finish];
}

- (ATRDocument *)documentWithParagraphs:(NSArray<NSString *> *)paragraphs {
    return [self documentWithParagraphs:paragraphs paragraphStyle:{} textStyle:{}];
}

- (ATRTextLayout *)layoutOfAttachment:(ATRAttachmentDescriptor)descriptor width:(double)width {
    ATRDocumentBuilder *builder = [[ATRDocumentBuilder alloc] init];
    int32_t font = [builder registerFont:[self font]];
    [builder beginParagraph:{} textStyle:fontStyle(font)];
    [builder appendText:@"x"];
    [builder appendAttachment:descriptor accessibilityLabel:nil];
    [builder appendText:@"y"];
    [builder endParagraph];
    return [[builder finish] layoutWithContainer:container(width) truncationToken:nil];
}

// MARK: Containers

- (void)testNonPositiveOrNaNWidthLaysOutNothing {
    ATRDocument *document = [self documentWithParagraphs:@[@"Text"]];

    for (double width : {0.0, -10.0, static_cast<double>(NAN)}) {
        ATRTextLayout *layout = [document layoutWithContainer:container(width) truncationToken:nil];
        XCTAssertEqual(layout.lineCount, 0u, @"width %f", width);
        XCTAssertTrue(CGSizeEqualToSize(layout.size, CGSizeZero));
        XCTAssertFalse(layout.truncated);
    }
}

- (void)testInfiniteWidthNeverWrapsOrAligns {
    ATRDocument *document = [self documentWithParagraphs:@[kLongText] paragraphStyle:alignment(ATRTextAlignmentRight) textStyle:{}];
    ATRTextLayout *layout = [document layoutWithContainer:container(INFINITY) truncationToken:nil];
    ATRLineInfo line = [layout lineAtIndex:0];

    XCTAssertEqual(layout.lineCount, 1u);
    XCTAssertEqual(CGRectGetMinX(line.frame), 0);
    XCTAssertEqualWithAccuracy(layout.size.width, CGRectGetWidth(line.frame), 0.001);
    XCTAssertTrue(isfinite(layout.size.width));
}

- (void)testVeryNarrowWidthStillMakesProgress {
    ATRDocument *document = [self documentWithParagraphs:@[@"abc", @"Supercalifragilistic"]];
    ATRTextLayout *layout = [document layoutWithContainer:container(1) truncationToken:nil];

    // Every line holds at least one character, so layout terminates even
    // when nothing fits.
    XCTAssertEqual(layout.lineCount, 3u + 20u);

    for (NSUInteger index = 0; index < layout.lineCount; ++index) {
        XCTAssertEqual([layout lineAtIndex:index].length, 1u);
    }
}

- (void)testLongWordsBreakInsideTheWord {
    NSString *word = @"Pneumonoultramicroscopicsilicovolcanoconiosis";
    ATRTextLayout *layout = [[self documentWithParagraphs:@[word]] layoutWithContainer:container(80)
                                                                         truncationToken:nil];
    NSUInteger total = 0;

    XCTAssertGreaterThan(layout.lineCount, 2u);

    for (NSUInteger index = 0; index < layout.lineCount; ++index) {
        ATRLineInfo line = [layout lineAtIndex:index];
        XCTAssertLessThanOrEqual(CGRectGetMaxX(line.frame), 80 + kTolerance);
        total += line.length;
    }

    XCTAssertEqual(total, word.length);
}

- (void)testMaximumLinesAboveTheLineCountDoesNotTruncate {
    ATRDocument *document = [self documentWithParagraphs:@[kLongText]];
    ATRTextLayout *free = [document layoutWithContainer:container(120) truncationToken:nil];
    ATRTextContainer limited = container(120);
    limited.maximumNumberOfLines = static_cast<uint32_t>(free.lineCount);
    ATRTextLayout *exact = [document layoutWithContainer:limited truncationToken:nil];
    limited.maximumNumberOfLines = 100;
    ATRTextLayout *loose = [document layoutWithContainer:limited truncationToken:nil];

    XCTAssertFalse(exact.truncated);
    XCTAssertFalse(loose.truncated);
    XCTAssertEqual(exact.lineCount, free.lineCount);
    XCTAssertTrue(CGSizeEqualToSize(exact.size, free.size));
}

- (void)testMaximumHeightThatFitsExactlyDoesNotTruncate {
    ATRDocument *document = [self documentWithParagraphs:@[kLongText, @"Second"]];
    ATRTextLayout *free = [document layoutWithContainer:container(120) truncationToken:nil];
    ATRTextContainer limited = container(120);
    limited.maxHeight = free.size.height;
    ATRTextLayout *exact = [document layoutWithContainer:limited truncationToken:nil];
    limited.maxHeight = free.size.height - 1;
    ATRTextLayout *short_ = [document layoutWithContainer:limited truncationToken:nil];

    XCTAssertFalse(exact.truncated);
    XCTAssertEqual(exact.lineCount, free.lineCount);
    XCTAssertTrue(short_.truncated);
    XCTAssertEqual(short_.lineCount, free.lineCount - 1);
    XCTAssertLessThanOrEqual(short_.size.height, free.size.height - 1);
}

- (void)testBothLimitsUseTheTighterOne {
    ATRDocument *document = [self documentWithParagraphs:@[kLongText]];
    ATRTextLayout *free = [document layoutWithContainer:container(100) truncationToken:nil];
    ATRTextContainer limited = container(100);
    limited.maximumNumberOfLines = 3;
    limited.maxHeight = CGRectGetMaxY([free lineAtIndex:0].frame) + 1;
    ATRTextLayout *layout = [document layoutWithContainer:limited truncationToken:nil];

    XCTAssertEqual(layout.lineCount, 1u);
    XCTAssertTrue(layout.truncated);
}

- (void)testLongerTokensShowLessText {
    ATRDocument *document = [self documentWithParagraphs:@[kLongText]];
    ATRTextContainer limited = container(150);
    limited.maximumNumberOfLines = 1;
    ATRTextLayout *ellipsis = [document layoutWithContainer:limited truncationToken:nil];
    ATRTextLayout *wordy = [document layoutWithContainer:limited truncationToken:@" … read more"];

    XCTAssertLessThan(NSMaxRange(wordy.visibleRange), NSMaxRange(ellipsis.visibleRange));
    XCTAssertLessThanOrEqual(CGRectGetMaxX([wordy lineAtIndex:0].frame), 150 + kTolerance);
}

- (void)testEmptyTruncationTokenStillCuts {
    ATRDocument *document = [self documentWithParagraphs:@[kLongText]];
    ATRTextContainer limited = container(150);
    limited.maximumNumberOfLines = 1;
    ATRTextLayout *layout = [document layoutWithContainer:limited truncationToken:@""];

    XCTAssertEqual(layout.lineCount, 1u);
    XCTAssertTrue(layout.truncated);
    XCTAssertLessThan(NSMaxRange(layout.visibleRange), kLongText.length);
    XCTAssertLessThanOrEqual(CGRectGetMaxX([layout lineAtIndex:0].frame), 150 + kTolerance);
}

- (void)testTokenWiderThanTheContainer {
    ATRDocument *document = [self documentWithParagraphs:@[kLongText]];
    ATRTextContainer limited = container(40);
    limited.maximumNumberOfLines = 1;
    ATRTextLayout *layout = [document layoutWithContainer:limited
                                          truncationToken:@"a very long truncation token indeed"];

    // CoreText may refuse to truncate; either way the layout stays valid.
    XCTAssertEqual(layout.lineCount, 1u);
    XCTAssertTrue(layout.truncated);
    XCTAssertLessThanOrEqual(NSMaxRange(layout.visibleRange), kLongText.length);
}

- (void)testLayoutIsDeterministic {
    ATRDocument *document = [self documentWithParagraphs:@[kLongText, @"", @"שלום world"]];
    ATRTextLayout *first = [document layoutWithContainer:container(140) truncationToken:nil];
    ATRTextLayout *second = [document layoutWithContainer:container(140) truncationToken:nil];

    XCTAssertEqual(first.lineCount, second.lineCount);
    XCTAssertTrue(CGSizeEqualToSize(first.size, second.size));

    for (NSUInteger index = 0; index < first.lineCount; ++index) {
        ATRLineInfo a = [first lineAtIndex:index];
        ATRLineInfo b = [second lineAtIndex:index];
        XCTAssertTrue(CGRectEqualToRect(a.frame, b.frame));
        XCTAssertEqual(a.location, b.location);
        XCTAssertEqual(a.length, b.length);
    }
}

- (void)testConcurrentLayoutsAgree {
    ATRDocument *document = [self documentWithParagraphs:@[kLongText, @"中文和 English 混排", @"שלום"]];
    CGSize expected = [document layoutWithContainer:container(130) truncationToken:nil].size;
    __block NSUInteger mismatches = 0;
    NSLock *lock = [[NSLock alloc] init];

    dispatch_apply(32, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^(size_t) {
        CGSize size = [document layoutWithContainer:container(130) truncationToken:nil].size;

        if (!CGSizeEqualToSize(size, expected)) {
            [lock lock];
            mismatches += 1;
            [lock unlock];
        }
    });

    XCTAssertEqual(mismatches, 0u);
}

// MARK: Paragraphs

- (void)testJustifiedLinesStretchExceptTheLast {
    ATRParagraphStyle justified = alignment(ATRTextAlignmentJustified);
    ATRTextLayout *left = [[self documentWithParagraphs:@[kLongText]] layoutWithContainer:container(150)
                                                                          truncationToken:nil];
    ATRTextLayout *stretched = [[self documentWithParagraphs:@[kLongText] paragraphStyle:justified textStyle:{}]
        layoutWithContainer:container(150)
            truncationToken:nil];

    XCTAssertEqual(left.lineCount, stretched.lineCount);
    NSUInteger last = stretched.lineCount - 1;

    for (NSUInteger index = 0; index < last; ++index) {
        ATRLineInfo line = [stretched lineAtIndex:index];
        XCTAssertGreaterThanOrEqual(CGRectGetWidth(line.frame), CGRectGetWidth([left lineAtIndex:index].frame) - 0.001);
        XCTAssertGreaterThan(CGRectGetWidth(line.frame), 150 - 10);
    }

    XCTAssertEqualWithAccuracy(
        CGRectGetWidth([stretched lineAtIndex:last].frame),
        CGRectGetWidth([left lineAtIndex:last].frame),
        0.001
    );
}

- (void)testExplicitRightToLeftDirectionAlignsLatinTextRight {
    ATRParagraphStyle rightToLeft = {};
    rightToLeft.fields = ATRParagraphStyleFieldWritingDirection;
    rightToLeft.writingDirection = ATRWritingDirectionRightToLeft;
    ATRTextLayout *layout = [[self documentWithParagraphs:@[@"Hello"] paragraphStyle:rightToLeft textStyle:{}]
        layoutWithContainer:container(300)
            truncationToken:nil];

    XCTAssertEqualWithAccuracy(CGRectGetMaxX([layout lineAtIndex:0].frame), 300, kTolerance);

    // Explicit left alignment wins over the direction's natural side.
    rightToLeft.fields |= ATRParagraphStyleFieldAlignment;
    rightToLeft.alignment = ATRTextAlignmentLeft;
    ATRTextLayout *left = [[self documentWithParagraphs:@[@"Hello"] paragraphStyle:rightToLeft textStyle:{}]
        layoutWithContainer:container(300)
            truncationToken:nil];
    XCTAssertEqualWithAccuracy(CGRectGetMinX([left lineAtIndex:0].frame), 0, kTolerance);
}

- (void)testEmptyParagraphsTakeTheirFontHeight {
    ATRDocumentBuilder *builder = [[ATRDocumentBuilder alloc] init];
    ATRPlatformFont *big = [ATRPlatformFont systemFontOfSize:40];
    int32_t font = [builder registerFont:big];
    [builder beginParagraph:{} textStyle:fontStyle(font)];
    [builder endParagraph];
    ATRTextLayout *layout = [[builder finish] layoutWithContainer:container(300) truncationToken:nil];
    CTFontRef ctFont = (__bridge CTFontRef)big;

    XCTAssertEqual(layout.lineCount, 1u);
    XCTAssertEqualWithAccuracy(
        layout.size.height,
        CTFontGetAscent(ctFont) + CTFontGetDescent(ctFont) + CTFontGetLeading(ctFont),
        0.001
    );
    XCTAssertEqual(layout.size.width, 0);
}

- (void)testSpacingIsOnlyBetweenLines {
    ATRParagraphStyle spaced = {};
    spaced.fields = ATRParagraphStyleFieldLineSpacing | ATRParagraphStyleFieldParagraphSpacing;
    spaced.lineSpacing = 10;
    spaced.paragraphSpacing = 30;
    ATRTextLayout *plain = [[self documentWithParagraphs:@[@"One"]] layoutWithContainer:container(300)
                                                                       truncationToken:nil];
    ATRTextLayout *single = [[self documentWithParagraphs:@[@"One"] paragraphStyle:spaced textStyle:{}]
        layoutWithContainer:container(300)
            truncationToken:nil];

    // No spacing before the first line or after the last one.
    XCTAssertEqualWithAccuracy(single.size.height, plain.size.height, 0.001);
    XCTAssertEqual(CGRectGetMinY([single lineAtIndex:0].frame), 0);
}

- (void)testParagraphSpacingComesFromTheEarlierParagraph {
    ATRDocumentBuilder *builder = [[ATRDocumentBuilder alloc] init];
    int32_t font = [builder registerFont:[self font]];
    ATRParagraphStyle wide = {};
    wide.fields = ATRParagraphStyleFieldParagraphSpacing;
    wide.paragraphSpacing = 40;
    [builder beginParagraph:wide textStyle:fontStyle(font)];
    [builder appendText:@"A"];
    [builder endParagraph];
    [builder beginParagraph:{} textStyle:fontStyle(font)];
    [builder appendText:@"B"];
    [builder endParagraph];
    [builder beginParagraph:{} textStyle:fontStyle(font)];
    [builder appendText:@"C"];
    [builder endParagraph];
    ATRTextLayout *layout = [[builder finish] layoutWithContainer:container(300) truncationToken:nil];

    double firstGap = CGRectGetMinY([layout lineAtIndex:1].frame) - CGRectGetMaxY([layout lineAtIndex:0].frame);
    double secondGap = CGRectGetMinY([layout lineAtIndex:2].frame) - CGRectGetMaxY([layout lineAtIndex:1].frame);
    XCTAssertEqualWithAccuracy(firstGap, 40, 0.001);
    XCTAssertEqualWithAccuracy(secondGap, 0, 0.001);
}

// MARK: Text styles

- (void)testKernWidensText {
    ATRTextStyle kerned = {};
    kerned.fields = ATRTextStyleFieldKern;
    kerned.kern = 5;
    NSString *text = @"abcdef";
    ATRTextLayout *plain = [[self documentWithParagraphs:@[text]] layoutWithContainer:container(INFINITY)
                                                                      truncationToken:nil];
    ATRTextLayout *wide = [[self documentWithParagraphs:@[text] paragraphStyle:{} textStyle:kerned]
        layoutWithContainer:container(INFINITY)
            truncationToken:nil];

    double added = wide.size.width - plain.size.width;
    XCTAssertGreaterThanOrEqual(added, 5 * (text.length - 1) - kTolerance);
    XCTAssertLessThanOrEqual(added, 5 * text.length + kTolerance);
}

- (void)testBaselineOffsetGrowsAMixedLine {
    auto layoutWithOffset = [&](double offset) {
        ATRDocumentBuilder *builder = [[ATRDocumentBuilder alloc] init];
        int32_t font = [builder registerFont:[self font]];
        ATRTextStyle shifted = fontStyle(font);
        shifted.fields |= ATRTextStyleFieldBaselineOffset;
        shifted.baselineOffset = offset;
        [builder beginParagraph:{} textStyle:fontStyle(font)];
        [builder appendText:@"x"];
        [builder pushSpan:shifted interaction:ATRNoInteraction];
        [builder appendText:@"2"];
        [builder popSpan];
        [builder endParagraph];
        return [[builder finish] layoutWithContainer:container(300) truncationToken:nil];
    };
    ATRTextLayout *plain = layoutWithOffset(0);
    ATRTextLayout *up = layoutWithOffset(10);
    ATRTextLayout *down = layoutWithOffset(-10);

    // A superscript adds room above the baseline, a subscript below it.
    XCTAssertEqualWithAccuracy(up.size.height, plain.size.height + 10, 0.001);
    XCTAssertEqualWithAccuracy([up lineAtIndex:0].baseline, [plain lineAtIndex:0].baseline + 10, 0.001);
    XCTAssertEqualWithAccuracy(down.size.height, plain.size.height + 10, 0.001);
    XCTAssertEqualWithAccuracy([down lineAtIndex:0].baseline, [plain lineAtIndex:0].baseline, 0.001);
}

- (void)testBaselineOffsetOnAWholeLineMovesItsBox {
    ATRTextStyle raised = {};
    raised.fields = ATRTextStyleFieldBaselineOffset;
    raised.baselineOffset = 10;
    ATRTextLayout *plain = [[self documentWithParagraphs:@[@"Text"]] layoutWithContainer:container(300)
                                                                         truncationToken:nil];
    ATRTextLayout *up = [[self documentWithParagraphs:@[@"Text"] paragraphStyle:{} textStyle:raised]
        layoutWithContainer:container(300)
            truncationToken:nil];

    // The line box follows the shifted glyphs, so nothing hangs outside it
    // and the glyphs keep their distance from the line top.
    double plainTopToGlyphs = [plain lineAtIndex:0].baseline;
    double raisedTopToGlyphs = [up lineAtIndex:0].baseline - 10;
    XCTAssertEqualWithAccuracy(raisedTopToGlyphs, plainTopToGlyphs, 0.001);
    XCTAssertLessThanOrEqual([up lineAtIndex:0].drawnBottom, CGRectGetMaxY([up lineAtIndex:0].frame) + 0.001);
}

- (void)testMixedFontSizesTakeTheTallestLine {
    ATRDocumentBuilder *builder = [[ATRDocumentBuilder alloc] init];
    int32_t small = [builder registerFont:[ATRPlatformFont systemFontOfSize:12]];
    ATRPlatformFont *bigFont = [ATRPlatformFont systemFontOfSize:36];
    int32_t big = [builder registerFont:bigFont];
    [builder beginParagraph:{} textStyle:fontStyle(small)];
    [builder appendText:@"small "];
    [builder pushSpan:fontStyle(big) interaction:ATRNoInteraction];
    [builder appendText:@"BIG"];
    [builder popSpan];
    [builder endParagraph];
    ATRTextLayout *layout = [[builder finish] layoutWithContainer:container(400) truncationToken:nil];
    CTFontRef ctFont = (__bridge CTFontRef)bigFont;

    XCTAssertEqualWithAccuracy([layout lineAtIndex:0].baseline, CTFontGetAscent(ctFont), 0.001);
    XCTAssertGreaterThanOrEqual(layout.size.height, CTFontGetAscent(ctFont) + CTFontGetDescent(ctFont) - 0.001);
}

// MARK: Attachments

- (void)testAttachmentAlignments {
    ATRPlatformFont *font = [self font];
    CTFontRef ctFont = (__bridge CTFontRef)font;
    double capHeight = CTFontGetCapHeight(ctFont);
    double descent = CTFontGetDescent(ctFont);

    auto frameFor = [&](ATRAttachmentAlignmentKind kind, double offset) {
        ATRAttachmentDescriptor descriptor = fixedAttachment(10, 8);
        descriptor.alignmentKind = kind;
        descriptor.alignmentOffset = offset;
        ATRTextLayout *layout = [self layoutOfAttachment:descriptor width:300];
        return std::make_pair([layout attachmentFrameAtIndex:0].frame, [layout lineAtIndex:0].baseline);
    };

    auto [baseline, baselineY] = frameFor(ATRAttachmentAlignmentKindBaseline, 0);
    XCTAssertEqualWithAccuracy(CGRectGetMaxY(baseline), baselineY, 0.001);

    auto [top, topY] = frameFor(ATRAttachmentAlignmentKindTop, 0);
    XCTAssertEqualWithAccuracy(CGRectGetMinY(top), topY - capHeight, 0.001);

    auto [bottom, bottomY] = frameFor(ATRAttachmentAlignmentKindBottom, 0);
    XCTAssertEqualWithAccuracy(CGRectGetMaxY(bottom), bottomY + descent, 0.001);

    auto [center, centerY] = frameFor(ATRAttachmentAlignmentKindCenter, 0);
    XCTAssertEqualWithAccuracy(CGRectGetMidY(center), centerY - (capHeight - descent) / 2, 0.001);

    auto [offset, offsetY] = frameFor(ATRAttachmentAlignmentKindOffset, 5);
    XCTAssertEqualWithAccuracy(CGRectGetMaxY(offset), offsetY - 5, 0.001);
}

- (void)testTallAttachmentsGrowTheirLine {
    ATRTextLayout *plain = [[self documentWithParagraphs:@[@"xy"]] layoutWithContainer:container(300)
                                                                       truncationToken:nil];
    ATRTextLayout *layout = [self layoutOfAttachment:fixedAttachment(10, 80) width:300];
    ATRAttachmentFrame frame = [layout attachmentFrameAtIndex:0];

    XCTAssertGreaterThan(layout.size.height, 80);
    XCTAssertGreaterThan(layout.size.height, plain.size.height);
    XCTAssertGreaterThanOrEqual(CGRectGetMinY(frame.frame), -0.001);
}

- (void)testAdaptiveImagesNeverUpscaleAndRespectLimits {
    ATRAttachmentDescriptor small = adaptiveAttachment(40, 20);
    small.fields |= ATRAttachmentFieldMaxWidth;
    small.maxWidth = 100;
    XCTAssertTrue(CGSizeEqualToSize([[self layoutOfAttachment:small width:300] attachmentFrameAtIndex:0].frame.size, CGSizeMake(40, 20)));

    ATRAttachmentDescriptor capped = adaptiveAttachment(40, 20);
    capped.fields |= ATRAttachmentFieldMaxHeight;
    capped.maxHeight = 10;
    XCTAssertTrue(CGSizeEqualToSize([[self layoutOfAttachment:capped width:300] attachmentFrameAtIndex:0].frame.size, CGSizeMake(20, 10)));

    // Both limits apply; the tighter one wins and the aspect ratio holds.
    ATRAttachmentDescriptor both = adaptiveAttachment(400, 100);
    both.fields |= ATRAttachmentFieldMaxWidth | ATRAttachmentFieldMaxHeight;
    both.maxWidth = 200;
    both.maxHeight = 20;
    XCTAssertTrue(CGSizeEqualToSize([[self layoutOfAttachment:both width:300] attachmentFrameAtIndex:0].frame.size, CGSizeMake(80, 20)));

    // Without limits the container width is the limit, and an infinite
    // container keeps the content size.
    ATRAttachmentDescriptor huge = adaptiveAttachment(1000, 500);
    XCTAssertTrue(CGSizeEqualToSize([[self layoutOfAttachment:huge width:300] attachmentFrameAtIndex:0].frame.size, CGSizeMake(300, 150)));
    XCTAssertTrue(CGSizeEqualToSize([[self layoutOfAttachment:huge width:INFINITY] attachmentFrameAtIndex:0].frame.size, CGSizeMake(1000, 500)));
}

- (void)testDegenerateContentSizesCollapse {
    ATRAttachmentDescriptor flat = adaptiveAttachment(100, 0);
    flat.fields |= ATRAttachmentFieldContentSize;
    ATRTextLayout *layout = [self layoutOfAttachment:flat width:300];
    CGRect frame = [layout attachmentFrameAtIndex:0].frame;

    XCTAssertEqual(CGRectGetWidth(frame), 0);
    XCTAssertTrue(isfinite(CGRectGetHeight(frame)));
    XCTAssertEqual(layout.lineCount, 1u);
}

- (void)testLoadedContentSizeReplacesTheDescriptor {
    ATRDocumentBuilder *builder = [[ATRDocumentBuilder alloc] init];
    int32_t font = [builder registerFont:[self font]];
    ATRAttachmentDescriptor unsized = adaptiveAttachment(0, 0);
    unsized.fields |= ATRAttachmentFieldMaxWidth;
    unsized.maxWidth = 50;
    unsized.pipeline = ATRImagePipelineAsyncImage;
    [builder beginParagraph:{} textStyle:fontStyle(font)];
    uint32_t attachment = [builder appendAttachment:unsized accessibilityLabel:nil];
    [builder endParagraph];
    ATRDocument *document = [builder finish];

    CGSize loaded = CGSizeMake(200, 100);
    NSDictionary *sizes = @{@(attachment): [NSValue valueWithBytes:&loaded objCType:@encode(CGSize)]};
    ATRTextLayout *layout = [document layoutWithContainer:container(300)
                                          truncationToken:nil
                                   attachmentContentSizes:sizes];

    XCTAssertTrue(CGSizeEqualToSize([layout attachmentFrameAtIndex:0].frame.size, CGSizeMake(50, 25)));
    XCTAssertEqualObjects(layout.attachmentContentSizes, sizes);

    // Sizes for unknown attachments are ignored.
    NSDictionary *unknown = @{@99: [NSValue valueWithBytes:&loaded objCType:@encode(CGSize)]};
    ATRTextLayout *ignored = [document layoutWithContainer:container(300)
                                           truncationToken:nil
                                    attachmentContentSizes:unknown];
    XCTAssertEqual(CGRectGetWidth([ignored attachmentFrameAtIndex:0].frame), 0);
}

- (void)testAttachmentWiderThanTheContainerTakesItsOwnLine {
    ATRTextLayout *layout = [self layoutOfAttachment:fixedAttachment(200, 10) width:100];

    XCTAssertEqual(layout.attachmentFrameCount, 1u);
    XCTAssertGreaterThanOrEqual(layout.lineCount, 2u);
    ATRAttachmentFrame frame = [layout attachmentFrameAtIndex:0];
    XCTAssertEqualWithAccuracy(CGRectGetWidth(frame.frame), 200, 0.001);
    XCTAssertEqualWithAccuracy(CGRectGetMinX(frame.frame), 0, kTolerance);
}

- (void)testSpacerHeights {
    ATRAttachmentDescriptor inferred = fixedAttachment(12, 0);
    inferred.kind = ATRAttachmentKindSpacer;
    inferred.fields = ATRAttachmentFieldInferredHeight;
    ATRAttachmentDescriptor tall = fixedAttachment(12, 50);
    tall.kind = ATRAttachmentKindSpacer;

    ATRTextLayout *plain = [[self documentWithParagraphs:@[@"xy"]] layoutWithContainer:container(300)
                                                                       truncationToken:nil];
    ATRTextLayout *inferredLayout = [self layoutOfAttachment:inferred width:300];
    ATRTextLayout *tallLayout = [self layoutOfAttachment:tall width:300];

    XCTAssertEqualWithAccuracy(inferredLayout.size.height, plain.size.height, 0.001);
    XCTAssertEqualWithAccuracy(inferredLayout.size.width, plain.size.width + 12, 0.01);
    XCTAssertEqualWithAccuracy(CGRectGetHeight([tallLayout attachmentFrameAtIndex:0].frame), 50, 0.001);
    XCTAssertGreaterThan(tallLayout.size.height, 50);
}

// MARK: Annotations

- (void)testDocumentScopeGradientJoinsAcrossParagraphs {
    ATRDocumentBuilder *builder = [[ATRDocumentBuilder alloc] init];
    int32_t font = [builder registerFont:[self font]];
    int32_t colors[] = {0, 0};
    int32_t gradient = [builder registerGradientWithColors:colors
                                                 locations:nil
                                                     count:2
                                                descriptor:{0, 0, 1, 1, ATRGradientScopeDocument}];
    ATRTextStyle fill = fontStyle(font);
    fill.fields |= ATRTextStyleFieldForeground;
    fill.foreground = {ATRFillKindGradient, gradient};

    for (NSString *text in @[@"First", @"Second", @"Third"]) {
        [builder beginParagraph:{} textStyle:fill];
        [builder appendText:text];
        [builder endParagraph];
    }

    ATRTextLayout *layout = [[builder finish] layoutWithContainer:container(300) truncationToken:nil];

    XCTAssertEqual(layout.gradientGroupCount, 1u);
    ATRGradientGroupInfo group = [layout gradientGroupAtIndex:0];
    XCTAssertEqual(group.memberCount, 3u);
    XCTAssertEqual(group.scopeInstance, 0u);
    XCTAssertLessThanOrEqual(CGRectGetMinY(group.rect), CGRectGetMinY([layout lineAtIndex:0].frame) + 0.001 + 10);
    XCTAssertGreaterThan(CGRectGetMaxY(group.rect), CGRectGetMinY([layout lineAtIndex:2].frame));
}

- (void)testGradientUnderlineSharesTheTextGroup {
    ATRDocumentBuilder *builder = [[ATRDocumentBuilder alloc] init];
    int32_t font = [builder registerFont:[self font]];
    int32_t colors[] = {0, 0};
    int32_t gradient = [builder registerGradientWithColors:colors
                                                 locations:nil
                                                     count:2
                                                descriptor:{0, 0.5, 1, 0.5, ATRGradientScopeParagraph}];
    ATRTextStyle fill = fontStyle(font);
    fill.fields |= ATRTextStyleFieldForeground | ATRTextStyleFieldUnderline;
    fill.foreground = {ATRFillKindGradient, gradient};
    fill.underline = solidUnderline();
    [builder beginParagraph:{} textStyle:fill];
    [builder appendText:@"Glow"];
    [builder endParagraph];
    ATRTextLayout *layout = [[builder finish] layoutWithContainer:container(300) truncationToken:nil];

    XCTAssertEqual(layout.gradientGroupCount, 1u);
    XCTAssertEqual(layout.decorationCount, 1u);
    XCTAssertEqual([layout decorationAtIndex:0].gradientGroup, 0);
}

- (void)testUnderlinesNeverMergeAcrossLines {
    ATRTextStyle underlined = {};
    underlined.fields = ATRTextStyleFieldUnderline;
    underlined.underline = solidUnderline();
    ATRTextLayout *layout = [[self documentWithParagraphs:@[kLongText] paragraphStyle:{} textStyle:underlined]
        layoutWithContainer:container(120)
            truncationToken:nil];

    XCTAssertEqual(layout.decorationCount, layout.lineCount);

    for (NSUInteger index = 0; index < layout.decorationCount; ++index) {
        ATRDecorationInfo decoration = [layout decorationAtIndex:index];
        ATRLineInfo line = [layout lineAtIndex:decoration.line];
        XCTAssertEqual(decoration.line, index);
        XCTAssertGreaterThan(CGRectGetMidY(decoration.rect), line.baseline);
        XCTAssertLessThan(CGRectGetMidY(decoration.rect), CGRectGetMaxY(line.frame));
    }
}

- (void)testUnderlineThicknessIsHonored {
    ATRTextStyle thick = {};
    thick.fields = ATRTextStyleFieldUnderline;
    thick.underline = solidUnderline();
    thick.underline.thickness = 3;
    ATRTextStyle automatic = thick;
    automatic.underline.thickness = 0;
    ATRTextLayout *layout = [[self documentWithParagraphs:@[@"Thick"] paragraphStyle:{} textStyle:thick]
        layoutWithContainer:container(300)
            truncationToken:nil];
    ATRTextLayout *fontLayout = [[self documentWithParagraphs:@[@"Thin"] paragraphStyle:{} textStyle:automatic]
        layoutWithContainer:container(300)
            truncationToken:nil];

    XCTAssertEqualWithAccuracy(CGRectGetHeight([layout decorationAtIndex:0].rect), 3, 0.001);
    XCTAssertGreaterThan(CGRectGetHeight([fontLayout decorationAtIndex:0].rect), 0);
}

- (void)testHitRegionsMergeAcrossStylesAndSplitAcrossLines {
    ATRDocumentBuilder *builder = [[ATRDocumentBuilder alloc] init];
    int32_t font = [builder registerFont:[self font]];
    int32_t bold = [builder registerFont:[ATRPlatformFont boldSystemFontOfSize:16]];
    ATRGesture tap = {ATRGestureKindTap, 1, 0};
    uint32_t link = [builder registerInteractionWithGesture:tap];

    [builder beginParagraph:{} textStyle:fontStyle(font)];
    [builder appendText:@"Go "];
    [builder pushSpan:{} interaction:link];
    [builder appendText:@"plain "];
    [builder pushSpan:fontStyle(bold) interaction:ATRNoInteraction];
    [builder appendText:@"bold"];
    [builder popSpan];
    [builder popSpan];
    [builder appendText:@" end"];
    [builder endParagraph];
    [builder beginParagraph:{} textStyle:fontStyle(font)];
    [builder pushSpan:{} interaction:link];
    [builder appendText:kLongText];
    [builder popSpan];
    [builder endParagraph];
    ATRTextLayout *layout = [[builder finish] layoutWithContainer:container(150) truncationToken:nil];

    NSUInteger firstLineRegions = 0;
    NSUInteger laterRegions = 0;

    for (NSUInteger index = 0; index < layout.hitRegionCount; ++index) {
        ATRHitRegion region = [layout hitRegionAtIndex:index];
        ATRLineInfo line = [layout lineAtIndex:region.line];
        XCTAssertEqualWithAccuracy(CGRectGetMinY(region.rect), CGRectGetMinY(line.frame), 0.001);
        XCTAssertEqualWithAccuracy(CGRectGetHeight(region.rect), CGRectGetHeight(line.frame), 0.001);

        if (region.line == 0) {
            ++firstLineRegions;
        } else {
            ++laterRegions;
        }
    }

    // Plain and bold runs in one span are one region.
    XCTAssertEqual(firstLineRegions, 1u);
    XCTAssertEqual(laterRegions, layout.lineCount - 1);
    XCTAssertEqual([layout rectsForInteraction:link].count, layout.hitRegionCount);
    XCTAssertEqualObjects([layout interactionsInSet:[layout hitRegionAtIndex:0].interactionSet], @[@(link)]);
}

- (void)testZeroWidthRunsHaveNoHitRegion {
    ATRDocumentBuilder *builder = [[ATRDocumentBuilder alloc] init];
    int32_t font = [builder registerFont:[self font]];
    ATRGesture tap = {ATRGestureKindTap, 1, 0};
    uint32_t link = [builder registerInteractionWithGesture:tap];
    ATRAttachmentDescriptor unsized = adaptiveAttachment(0, 0);
    unsized.pipeline = ATRImagePipelineAsyncImage;
    [builder beginParagraph:{} textStyle:fontStyle(font)];
    [builder appendText:@"x"];
    [builder pushSpan:{} interaction:link];
    [builder appendAttachment:unsized accessibilityLabel:nil];
    [builder popSpan];
    [builder endParagraph];
    ATRTextLayout *layout = [[builder finish] layoutWithContainer:container(300) truncationToken:nil];

    XCTAssertEqual(layout.hitRegionCount, 0u);
    XCTAssertEqual([layout rectsForInteraction:link].count, 0u);
}

@end
