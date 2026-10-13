// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#import <XCTest/XCTest.h>

#import "ATRDocumentBuilder.h"

#include <vector>

namespace {

constexpr double kTolerance = 0.5;

ATRTextContainer container(double width) {
    return {width, INFINITY, 0, ATRLineHeightModeTypographic};
}

ATRTextContainer limitedContainer(double width, uint32_t maxLines) {
    return {width, INFINITY, maxLines, ATRLineHeightModeTypographic};
}

ATRTextStyle fontStyle(int32_t font) {
    ATRTextStyle style = {};
    style.fields = ATRTextStyleFieldFont;
    style.font = font;
    return style;
}

ATRParagraphStyle spacing(double line, double paragraph) {
    ATRParagraphStyle style = {};
    style.fields = ATRParagraphStyleFieldLineSpacing | ATRParagraphStyleFieldParagraphSpacing;
    style.lineSpacing = line;
    style.paragraphSpacing = paragraph;
    return style;
}

ATRParagraphStyle alignment(ATRTextAlignment value) {
    ATRParagraphStyle style = {};
    style.fields = ATRParagraphStyleFieldAlignment;
    style.alignment = value;
    return style;
}

ATRTextPosition downstream(NSUInteger offset) {
    return {offset, ATRTextAffinityDownstream};
}

ATRTextPosition upstream(NSUInteger offset) {
    return {offset, ATRTextAffinityUpstream};
}

std::vector<ATRSelectionRect> selectionRects(ATRTextLayout *layout, NSRange range) {
    std::vector<ATRSelectionRect> result;

    for (NSValue *value in [layout selectionRectsForRange:range minY:-INFINITY maxY:INFINITY]) {
        ATRSelectionRect rect = {};
        [value getValue:&rect size:sizeof(rect)];
        result.push_back(rect);
    }

    return result;
}

CGPoint center(CGRect rect) {
    return CGPointMake(CGRectGetMidX(rect), CGRectGetMidY(rect));
}

NSString *const kLongText =
    @"The quick brown fox jumps over the lazy dog and keeps running across the field.";

} // namespace

@interface GeometryTests : XCTestCase
@end

@implementation GeometryTests

- (ATRPlatformFont *)font {
    return [ATRPlatformFont systemFontOfSize:16];
}

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

- (ATRTextLayout *)layoutOf:(NSArray<NSString *> *)paragraphs width:(double)width {
    return [[self documentWithParagraphs:paragraphs paragraphStyle:{}] layoutWithContainer:container(width)
                                                                            truncationToken:nil];
}

- (ATRTextLayout *)layoutOf:(NSArray<NSString *> *)paragraphs
             paragraphStyle:(ATRParagraphStyle)paragraphStyle
                      width:(double)width {
    return [[self documentWithParagraphs:paragraphs paragraphStyle:paragraphStyle]
        layoutWithContainer:container(width)
            truncationToken:nil];
}

// MARK: Text and lines

- (void)testTextLengthJoinsParagraphsWithOneSeparator {
    ATRDocument *document = [self documentWithParagraphs:@[@"Hello", @"", @"World"] paragraphStyle:{}];
    ATRTextLayout *layout = [document layoutWithContainer:container(300) truncationToken:nil];

    XCTAssertEqual(layout.textLength, 12u);
    XCTAssertTrue(NSEqualRanges(layout.visibleRange, NSMakeRange(0, 12)));
    XCTAssertEqualObjects([document textInRange:NSMakeRange(0, 12)], @"Hello\n\nWorld");
    XCTAssertEqualObjects([document textInRange:NSMakeRange(3, 5)], @"lo\n\nW");
    XCTAssertEqualObjects([document textInRange:NSMakeRange(5, 1)], @"\n");
    XCTAssertEqualObjects([document textInRange:NSMakeRange(7, 100)], @"World");
    XCTAssertEqualObjects([document textInRange:NSMakeRange(12, 1)], @"");
    XCTAssertEqualObjects([document textInRange:NSMakeRange(40, 1)], @"");
}

- (void)testLineRangesAreGlobalAndContiguous {
    ATRTextLayout *layout = [self layoutOf:@[kLongText, @"", @"Tail"] width:120];
    NSUInteger expected = 0;
    uint32_t paragraph = 0;

    for (NSUInteger index = 0; index < layout.lineCount; ++index) {
        ATRLineInfo line = [layout lineAtIndex:index];
        NSRange range = [layout rangeOfLineAtIndex:index];

        if (line.paragraph != paragraph) {
            // The separator sits between paragraphs and belongs to no line.
            expected += 1;
            paragraph = line.paragraph;
        }

        XCTAssertEqual(range.location, expected, @"line %lu", (unsigned long)index);
        XCTAssertEqual(range.length, line.length);
        expected = NSMaxRange(range);
    }

    XCTAssertEqual(expected, layout.textLength);
}

- (void)testEmptyParagraphLineHasAnEmptyRange {
    ATRTextLayout *layout = [self layoutOf:@[@"A", @"", @"B"] width:300];

    XCTAssertEqual(layout.lineCount, 3u);
    XCTAssertTrue(NSEqualRanges([layout rangeOfLineAtIndex:1], NSMakeRange(2, 0)));
    XCTAssertEqual([layout lineIndexContainingPosition:downstream(2)], 1u);
    XCTAssertEqual([layout lineIndexContainingPosition:downstream(3)], 2u);
}

- (void)testLineAtYSkipsGapsAndOutside {
    ATRTextLayout *layout = [self layoutOf:@[kLongText, @"Second"] paragraphStyle:spacing(6, 20) width:150];
    ATRLineInfo first = [layout lineAtIndex:0];
    ATRLineInfo second = [layout lineAtIndex:1];

    XCTAssertEqual([layout lineIndexAtY:CGRectGetMidY(first.frame)], 0u);
    XCTAssertEqual([layout lineIndexAtY:CGRectGetMinY(first.frame)], 0u);
    XCTAssertEqual([layout lineIndexAtY:CGRectGetMidY(second.frame)], 1u);
    XCTAssertEqual([layout lineIndexAtY:CGRectGetMaxY(first.frame) + 3], NSNotFound);
    XCTAssertEqual([layout lineIndexAtY:-1], NSNotFound);
    XCTAssertEqual([layout lineIndexAtY:layout.size.height + 1], NSNotFound);

    NSUInteger last = layout.lineCount - 1;
    ATRLineInfo lastOfFirst = [layout lineAtIndex:last - 1];
    ATRLineInfo paragraphStart = [layout lineAtIndex:last];
    double gap = (CGRectGetMaxY(lastOfFirst.frame) + CGRectGetMinY(paragraphStart.frame)) / 2;
    XCTAssertEqual([layout lineIndexAtY:gap], NSNotFound);
}

- (void)testLinesBetweenReturnsOverlappingLines {
    ATRTextLayout *layout = [self layoutOf:@[kLongText] paragraphStyle:spacing(4, 0) width:100];
    XCTAssertGreaterThan(layout.lineCount, 3u);
    ATRLineInfo second = [layout lineAtIndex:1];
    ATRLineInfo third = [layout lineAtIndex:2];

    NSRange all = [layout lineIndexesBetweenMinY:-INFINITY maxY:INFINITY];
    XCTAssertTrue(NSEqualRanges(all, NSMakeRange(0, layout.lineCount)));

    NSRange middle = [layout lineIndexesBetweenMinY:CGRectGetMidY(second.frame) maxY:CGRectGetMidY(third.frame)];
    XCTAssertTrue(NSEqualRanges(middle, NSMakeRange(1, 2)));

    // A gap overlaps no line, and the bounds are half-open.
    NSRange gap = [layout lineIndexesBetweenMinY:CGRectGetMaxY(second.frame) maxY:CGRectGetMinY(third.frame)];
    XCTAssertEqual(gap.length, 0u);

    NSRange below = [layout lineIndexesBetweenMinY:layout.size.height + 10 maxY:layout.size.height + 20];
    XCTAssertEqual(below.length, 0u);
}

- (void)testSoftBreakAffinityPicksTheLine {
    ATRTextLayout *layout = [self layoutOf:@[kLongText] width:120];
    NSRange first = [layout rangeOfLineAtIndex:0];
    NSUInteger breakOffset = NSMaxRange(first);

    XCTAssertEqual([layout lineIndexContainingPosition:downstream(breakOffset)], 1u);
    XCTAssertEqual([layout lineIndexContainingPosition:upstream(breakOffset)], 0u);
    XCTAssertEqual([layout lineIndexContainingPosition:upstream(0)], 0u);
    XCTAssertEqual([layout lineIndexContainingPosition:downstream(layout.textLength)], layout.lineCount - 1);
    XCTAssertEqual([layout lineIndexContainingPosition:downstream(layout.textLength + 1)], NSNotFound);
}

- (void)testParagraphEndIsOnTheLastLineOfItsParagraph {
    ATRTextLayout *layout = [self layoutOf:@[@"One", @"Two"] width:300];

    // Offset 3 is the separator; upstream or not, it ends the first line.
    XCTAssertEqual([layout lineIndexContainingPosition:downstream(3)], 0u);
    XCTAssertEqual([layout lineIndexContainingPosition:upstream(3)], 0u);
    XCTAssertEqual([layout lineIndexContainingPosition:upstream(4)], 1u);
}

// MARK: Hit testing

- (void)testCharacterIndexRoundTripsThroughSelectionRects {
    NSString *text = @"Hello, world";
    ATRTextLayout *layout = [self layoutOf:@[text] width:400];

    for (NSUInteger index = 0; index < text.length; ++index) {
        auto rects = selectionRects(layout, NSMakeRange(index, 1));
        XCTAssertEqual(rects.size(), 1u);
        XCTAssertEqual([layout characterIndexAtPoint:center(rects[0].rect)], index, @"index %lu", (unsigned long)index);
    }
}

- (void)testCharacterIndexIsNotFoundOffGlyphs {
    ATRTextLayout *layout = [self layoutOf:@[@"Short", @"Text"] paragraphStyle:spacing(0, 30) width:400];
    ATRLineInfo line = [layout lineAtIndex:0];

    XCTAssertEqual([layout characterIndexAtPoint:CGPointMake(CGRectGetMaxX(line.frame) + 20, 5)], NSNotFound);
    XCTAssertEqual([layout characterIndexAtPoint:CGPointMake(-5, 5)], NSNotFound);
    XCTAssertEqual([layout characterIndexAtPoint:CGPointMake(2, CGRectGetMaxY(line.frame) + 10)], NSNotFound);
    XCTAssertEqual([layout characterIndexAtPoint:CGPointMake(2, -1)], NSNotFound);
}

- (void)testCharacterIndexReturnsTheClusterStart {
    // "e" + combining acute, then a family emoji made of ZWJ sequences.
    NSString *family = @"\U0001F468‍\U0001F469‍\U0001F467";
    NSString *text = [NSString stringWithFormat:@"aéb%@c", family];
    ATRTextLayout *layout = [self layoutOf:@[text] width:400];

    auto accent = selectionRects(layout, NSMakeRange(1, 2));
    XCTAssertEqual(accent.size(), 1u);
    XCTAssertEqual([layout characterIndexAtPoint:center(accent[0].rect)], 1u);

    auto emoji = selectionRects(layout, NSMakeRange(4, family.length));
    XCTAssertEqual(emoji.size(), 1u);
    XCTAssertEqual([layout characterIndexAtPoint:center(emoji[0].rect)], 4u);
}

- (void)testClosestPositionClampsToLinesAndText {
    ATRTextLayout *layout = [self layoutOf:@[@"First line", @"Second"] paragraphStyle:spacing(0, 40) width:400];
    ATRLineInfo first = [layout lineAtIndex:0];
    ATRLineInfo second = [layout lineAtIndex:1];

    ATRTextPosition above = [layout closestPositionToPoint:CGPointMake(-50, -50)];
    XCTAssertEqual(above.offset, 0u);
    XCTAssertEqual(above.affinity, ATRTextAffinityDownstream);

    ATRTextPosition below = [layout closestPositionToPoint:CGPointMake(1000, layout.size.height + 50)];
    XCTAssertEqual(below.offset, layout.textLength);

    ATRTextPosition lineEnd = [layout closestPositionToPoint:CGPointMake(1000, CGRectGetMidY(first.frame))];
    XCTAssertEqual(lineEnd.offset, 10u);
    XCTAssertEqual(lineEnd.affinity, ATRTextAffinityDownstream);

    // In the paragraph gap, the nearer line wins.
    double gapTop = CGRectGetMaxY(first.frame);
    double gapBottom = CGRectGetMinY(second.frame);
    XCTAssertEqual([layout closestPositionToPoint:CGPointMake(0, gapTop + 5)].offset, 0u);
    XCTAssertEqual([layout closestPositionToPoint:CGPointMake(0, gapBottom - 5)].offset, 11u);
}

- (void)testClosestPositionPicksTheNearerCaret {
    NSString *text = @"Hello";
    ATRTextLayout *layout = [self layoutOf:@[text] width:400];

    for (NSUInteger index = 0; index <= text.length; ++index) {
        CGRect caret = [layout caretRectForPosition:downstream(index)];
        ATRTextPosition position = [layout closestPositionToPoint:CGPointMake(CGRectGetMinX(caret) + 0.4, 5)];
        XCTAssertEqual(position.offset, index);
    }
}

- (void)testClosestPositionAtSoftBreakIsUpstream {
    ATRTextLayout *layout = [self layoutOf:@[kLongText] width:120];
    ATRLineInfo first = [layout lineAtIndex:0];
    ATRTextPosition position = [layout closestPositionToPoint:CGPointMake(500, CGRectGetMidY(first.frame))];

    XCTAssertEqual(position.offset, NSMaxRange([layout rangeOfLineAtIndex:0]));
    XCTAssertEqual(position.affinity, ATRTextAffinityUpstream);
    XCTAssertEqual([layout lineIndexContainingPosition:position], 0u);

    ATRLineInfo second = [layout lineAtIndex:1];
    ATRTextPosition next = [layout closestPositionToPoint:CGPointMake(-10, CGRectGetMidY(second.frame))];
    XCTAssertEqual(next.offset, position.offset);
    XCTAssertEqual(next.affinity, ATRTextAffinityDownstream);
}

- (void)testClosestPositionNeverSplitsAnEmoji {
    NSString *family = @"\U0001F468‍\U0001F469‍\U0001F467";
    NSString *text = [NSString stringWithFormat:@"a%@b", family];
    ATRTextLayout *layout = [self layoutOf:@[text] width:400];
    CGRect emoji = selectionRects(layout, NSMakeRange(1, family.length))[0].rect;

    for (double fraction = 0.05; fraction < 1; fraction += 0.1) {
        double x = CGRectGetMinX(emoji) + CGRectGetWidth(emoji) * fraction;
        NSUInteger offset = [layout closestPositionToPoint:CGPointMake(x, CGRectGetMidY(emoji))].offset;
        XCTAssertTrue(offset == 1 || offset == 1 + family.length, @"offset %lu", (unsigned long)offset);
    }
}

- (void)testClosestPositionOnAnEmptyLine {
    ATRTextLayout *layout = [self layoutOf:@[@"A", @"", @"B"] width:300];
    ATRLineInfo empty = [layout lineAtIndex:1];
    ATRTextPosition position = [layout closestPositionToPoint:CGPointMake(100, CGRectGetMidY(empty.frame))];

    XCTAssertEqual(position.offset, 2u);
    XCTAssertEqual(position.affinity, ATRTextAffinityDownstream);
}

- (void)testAlignedLinesHitTestFromTheirOrigin {
    ATRTextLayout *layout = [self layoutOf:@[@"Right"] paragraphStyle:alignment(ATRTextAlignmentRight) width:300];
    ATRLineInfo line = [layout lineAtIndex:0];

    XCTAssertGreaterThan(CGRectGetMinX(line.frame), 200);
    XCTAssertEqual([layout closestPositionToPoint:CGPointMake(0, 5)].offset, 0u);
    XCTAssertEqual([layout characterIndexAtPoint:CGPointMake(10, 5)], NSNotFound);
    XCTAssertEqual([layout characterIndexAtPoint:CGPointMake(CGRectGetMinX(line.frame) + 2, 5)], 0u);
    XCTAssertEqualWithAccuracy(
        CGRectGetMinX([layout caretRectForPosition:downstream(0)]),
        CGRectGetMinX(line.frame),
        kTolerance
    );
}

// MARK: Carets

- (void)testCaretsAdvanceAndSpanTheLine {
    NSString *text = @"Hello";
    ATRTextLayout *layout = [self layoutOf:@[text] width:400];
    ATRLineInfo line = [layout lineAtIndex:0];
    double previous = -1;

    for (NSUInteger index = 0; index <= text.length; ++index) {
        CGRect caret = [layout caretRectForPosition:downstream(index)];
        XCTAssertEqual(CGRectGetWidth(caret), 0);
        XCTAssertEqualWithAccuracy(CGRectGetMinY(caret), CGRectGetMinY(line.frame), 0.001);
        XCTAssertEqualWithAccuracy(CGRectGetHeight(caret), CGRectGetHeight(line.frame), 0.001);
        XCTAssertGreaterThan(CGRectGetMinX(caret), previous);
        previous = CGRectGetMinX(caret);
    }

    XCTAssertEqualWithAccuracy(previous, CGRectGetMaxX(line.frame), kTolerance);
}

- (void)testCaretAtSoftBreakDependsOnAffinity {
    ATRTextLayout *layout = [self layoutOf:@[kLongText] width:120];
    NSUInteger breakOffset = NSMaxRange([layout rangeOfLineAtIndex:0]);
    CGRect up = [layout caretRectForPosition:upstream(breakOffset)];
    CGRect down = [layout caretRectForPosition:downstream(breakOffset)];

    XCTAssertEqualWithAccuracy(CGRectGetMinY(up), CGRectGetMinY([layout lineAtIndex:0].frame), 0.001);
    XCTAssertEqualWithAccuracy(CGRectGetMinY(down), CGRectGetMinY([layout lineAtIndex:1].frame), 0.001);
    XCTAssertGreaterThan(CGRectGetMinX(up), 50);
    XCTAssertEqualWithAccuracy(CGRectGetMinX(down), 0, kTolerance);
}

- (void)testCaretPastTheEndClampsToTheEnd {
    ATRTextLayout *layout = [self layoutOf:@[@"Hello"] width:400];
    CGRect end = [layout caretRectForPosition:downstream(5)];
    CGRect past = [layout caretRectForPosition:downstream(50)];

    XCTAssertTrue(CGRectEqualToRect(end, past));
}

- (void)testCaretOnEmptyLines {
    ATRTextLayout *layout = [self layoutOf:@[@"A", @"", @"B"] width:300];
    CGRect caret = [layout caretRectForPosition:downstream(2)];
    ATRLineInfo empty = [layout lineAtIndex:1];

    XCTAssertEqualWithAccuracy(CGRectGetMinX(caret), 0, 0.001);
    XCTAssertEqualWithAccuracy(CGRectGetMinY(caret), CGRectGetMinY(empty.frame), 0.001);
    XCTAssertGreaterThan(CGRectGetHeight(caret), 0);

    ATRTextLayout *centered = [self layoutOf:@[@""] paragraphStyle:alignment(ATRTextAlignmentCenter) width:300];
    XCTAssertEqualWithAccuracy(CGRectGetMinX([centered caretRectForPosition:downstream(0)]), 150, 0.001);
}

// MARK: Selection rects

- (void)testSelectionOnOneLineMatchesCarets {
    ATRTextLayout *layout = [self layoutOf:@[@"Hello, world"] width:400];
    auto rects = selectionRects(layout, NSMakeRange(2, 5));
    ATRLineInfo line = [layout lineAtIndex:0];

    XCTAssertEqual(rects.size(), 1u);
    XCTAssertEqualWithAccuracy(CGRectGetMinX(rects[0].rect), CGRectGetMinX([layout caretRectForPosition:downstream(2)]), kTolerance);
    XCTAssertEqualWithAccuracy(CGRectGetMaxX(rects[0].rect), CGRectGetMinX([layout caretRectForPosition:downstream(7)]), kTolerance);
    XCTAssertTrue(CGRectGetMinY(rects[0].rect) == CGRectGetMinY(line.frame));
    XCTAssertTrue(CGRectGetHeight(rects[0].rect) == CGRectGetHeight(line.frame));
    XCTAssertTrue(rects[0].containsStart);
    XCTAssertTrue(rects[0].containsEnd);
    XCTAssertFalse(rects[0].rightToLeft);
}

- (void)testSelectionAcrossLinesMarksItsEnds {
    ATRTextLayout *layout = [self layoutOf:@[kLongText] paragraphStyle:spacing(5, 0) width:120];
    NSRange range = NSMakeRange(2, layout.textLength - 4);
    auto rects = selectionRects(layout, range);

    XCTAssertEqual(rects.size(), layout.lineCount);

    for (size_t index = 0; index < rects.size(); ++index) {
        XCTAssertEqual(rects[index].line, index);
        XCTAssertEqual(rects[index].containsStart, index == 0);
        XCTAssertEqual(rects[index].containsEnd, index == rects.size() - 1);
        ATRLineInfo line = [layout lineAtIndex:index];
        XCTAssertEqualWithAccuracy(CGRectGetMinY(rects[index].rect), CGRectGetMinY(line.frame), 0.001);
        XCTAssertEqualWithAccuracy(CGRectGetHeight(rects[index].rect), CGRectGetHeight(line.frame), 0.001);
    }

    // Adjacent rects never overlap: each covers only its own line's height.
    for (size_t index = 1; index < rects.size(); ++index) {
        XCTAssertLessThanOrEqual(CGRectGetMaxY(rects[index - 1].rect), CGRectGetMinY(rects[index].rect));
    }
}

- (void)testSelectionSkipsEmptyLinesAndSeparators {
    ATRTextLayout *layout = [self layoutOf:@[@"Ab", @"", @"Cd"] width:300];
    auto all = selectionRects(layout, NSMakeRange(0, layout.textLength));

    XCTAssertEqual(all.size(), 2u);
    XCTAssertEqual(all[0].line, 0u);
    XCTAssertEqual(all[1].line, 2u);
    XCTAssertTrue(all[0].containsStart);
    XCTAssertTrue(all[1].containsEnd);

    XCTAssertEqual(selectionRects(layout, NSMakeRange(2, 2)).size(), 0u);
    XCTAssertEqual(selectionRects(layout, NSMakeRange(1, 0)).size(), 0u);
    XCTAssertEqual(selectionRects(layout, NSMakeRange(100, 3)).size(), 0u);
}

- (void)testHangingWhitespaceStaysInsideTheContainer {
    ATRTextLayout *layout = [self layoutOf:@[kLongText] width:120];

    for (const ATRSelectionRect &selection : selectionRects(layout, NSMakeRange(0, layout.textLength))) {
        XCTAssertGreaterThanOrEqual(CGRectGetMinX(selection.rect), 0);
        XCTAssertLessThanOrEqual(CGRectGetMaxX(selection.rect), 120);
    }

    for (NSUInteger index = 0; index < layout.lineCount; ++index) {
        NSUInteger end = NSMaxRange([layout rangeOfLineAtIndex:index]);
        XCTAssertLessThanOrEqual(CGRectGetMaxX([layout caretRectForPosition:upstream(end)]), 120);
    }
}

- (void)testSelectionClipsToTheVerticalWindow {
    ATRTextLayout *layout = [self layoutOf:@[kLongText] width:100];
    ATRLineInfo second = [layout lineAtIndex:1];
    ATRLineInfo third = [layout lineAtIndex:2];
    NSArray<NSValue *> *values = [layout selectionRectsForRange:NSMakeRange(0, layout.textLength)
                                                           minY:CGRectGetMidY(second.frame)
                                                           maxY:CGRectGetMidY(third.frame)];

    XCTAssertEqual(values.count, 2u);
    ATRSelectionRect first = {};
    [values.firstObject getValue:&first size:sizeof(first)];
    XCTAssertEqual(first.line, 1u);
    XCTAssertFalse(first.containsStart);
}

- (void)testSelectionInRightToLeftText {
    ATRTextLayout *layout = [self layoutOf:@[@"שלום עולם"] width:400];
    auto rects = selectionRects(layout, NSMakeRange(0, 4));

    XCTAssertEqual(rects.size(), 1u);
    XCTAssertTrue(rects[0].rightToLeft);
    // The first word of a right-to-left paragraph is on the right.
    ATRLineInfo line = [layout lineAtIndex:0];
    XCTAssertEqualWithAccuracy(CGRectGetMaxX(rects[0].rect), CGRectGetMaxX(line.frame), kTolerance);
    XCTAssertEqualWithAccuracy(
        CGRectGetMinX([layout caretRectForPosition:downstream(0)]),
        CGRectGetMaxX(line.frame),
        kTolerance
    );
}

- (void)testMixedDirectionSelectionSplitsIntoPieces {
    // Logical "abc " then Hebrew, then " def"; the Hebrew run is reversed on
    // screen, so "c" plus the first Hebrew letter are two separate pieces.
    NSString *text = @"abc אבג def";
    ATRTextLayout *layout = [self layoutOf:@[text] width:400];
    auto rects = selectionRects(layout, NSMakeRange(2, 3));

    XCTAssertEqual(rects.size(), 2u);
    XCTAssertFalse(rects[0].rightToLeft);
    XCTAssertTrue(rects[0].containsStart);
    XCTAssertTrue(rects[1].rightToLeft);
    XCTAssertTrue(rects[1].containsEnd);
    XCTAssertLessThan(CGRectGetMaxX(rects[0].rect), CGRectGetMinX(rects[1].rect) - 1);

    // The whole Hebrew word is one piece.
    auto word = selectionRects(layout, NSMakeRange(4, 3));
    XCTAssertEqual(word.size(), 1u);
    XCTAssertTrue(word[0].rightToLeft);
}

- (void)testAttachmentsSelectAsOneCharacter {
    ATRDocumentBuilder *builder = [[ATRDocumentBuilder alloc] init];
    int32_t font = [builder registerFont:[self font]];
    ATRAttachmentDescriptor image = {};
    image.sizeKind = ATRAttachmentSizeKindFixed;
    image.width = 30;
    image.height = 12;
    ATRAttachmentDescriptor spacer = image;
    spacer.kind = ATRAttachmentKindSpacer;
    spacer.width = 20;

    [builder beginParagraph:{} textStyle:fontStyle(font)];
    [builder appendText:@"A"];
    [builder appendAttachment:image accessibilityLabel:nil];
    [builder appendText:@"B"];
    [builder appendAttachment:spacer accessibilityLabel:nil];
    [builder appendText:@"C"];
    [builder endParagraph];
    ATRTextLayout *layout = [[builder finish] layoutWithContainer:container(400) truncationToken:nil];
    ATRLineInfo line = [layout lineAtIndex:0];

    XCTAssertEqual(layout.textLength, 5u);
    auto imageRects = selectionRects(layout, NSMakeRange(1, 1));
    XCTAssertEqual(imageRects.size(), 1u);
    XCTAssertEqualWithAccuracy(CGRectGetWidth(imageRects[0].rect), 30, 0.01);
    XCTAssertEqualWithAccuracy(CGRectGetHeight(imageRects[0].rect), CGRectGetHeight(line.frame), 0.001);
    XCTAssertEqualWithAccuracy(CGRectGetMinX(imageRects[0].rect), [layout attachmentFrameAtIndex:0].frame.origin.x, 0.01);
    XCTAssertEqual([layout characterIndexAtPoint:center(imageRects[0].rect)], 1u);

    auto spacerRects = selectionRects(layout, NSMakeRange(3, 1));
    XCTAssertEqual(spacerRects.size(), 1u);
    XCTAssertEqualWithAccuracy(CGRectGetWidth(spacerRects[0].rect), 20, 0.01);
    XCTAssertEqual([layout characterIndexAtPoint:center(spacerRects[0].rect)], 3u);

    XCTAssertTrue(NSEqualRanges([layout rangeEnclosingIndex:1 granularity:ATRTextGranularityCharacter], NSMakeRange(1, 1)));
}

- (void)testBoundingRectUnitesSelectionRects {
    ATRTextLayout *layout = [self layoutOf:@[kLongText] width:120];
    NSRange range = NSMakeRange(0, layout.textLength);
    CGRect bounds = [layout boundingRectForRange:range];

    XCTAssertEqualWithAccuracy(CGRectGetMinY(bounds), 0, 0.001);
    XCTAssertEqualWithAccuracy(CGRectGetMaxY(bounds), layout.size.height, 0.001);
    XCTAssertLessThanOrEqual(CGRectGetMaxX(bounds), 120 + kTolerance);
    XCTAssertTrue(CGRectIsNull([layout boundingRectForRange:NSMakeRange(3, 0)]));
}

- (void)testGlyphBoundsModeSelectionUsesTheGrownLineHeight {
    ATRDocument *document = [self documentWithParagraphs:@[@"ฎุ้ ญู้ ฐุ่"] paragraphStyle:{}];
    ATRTextLayout *layout = [document layoutWithContainer:{400, INFINITY, 0, ATRLineHeightModeGlyphBounds}
                                          truncationToken:nil];
    auto rects = selectionRects(layout, NSMakeRange(0, layout.textLength));
    ATRLineInfo line = [layout lineAtIndex:0];

    XCTAssertFalse(rects.empty());
    XCTAssertEqualWithAccuracy(CGRectGetHeight(rects[0].rect), CGRectGetHeight(line.frame), 0.001);
}

// MARK: Truncation

- (void)testTruncationLimitsTheVisibleRange {
    ATRDocument *document = [self documentWithParagraphs:@[kLongText, @"Hidden"] paragraphStyle:{}];
    ATRTextLayout *layout = [document layoutWithContainer:limitedContainer(120, 2) truncationToken:nil];
    NSRange visible = layout.visibleRange;
    NSRange last = [layout rangeOfLineAtIndex:1];

    XCTAssertTrue(layout.truncated);
    XCTAssertEqual(visible.location, 0u);
    XCTAssertEqual(NSMaxRange(visible), NSMaxRange(last));
    XCTAssertLessThan(NSMaxRange(visible), (NSUInteger)kLongText.length);
    XCTAssertEqual([layout lineIndexContainingPosition:downstream(NSMaxRange(visible) + 1)], NSNotFound);

    // Selecting everything only covers the visible text.
    auto all = selectionRects(layout, NSMakeRange(0, layout.textLength));
    auto shown = selectionRects(layout, visible);
    XCTAssertEqual(all.size(), shown.size());
    XCTAssertTrue(CGRectEqualToRect(all.back().rect, shown.back().rect));
    XCTAssertTrue(all.back().containsEnd);
    XCTAssertEqual(selectionRects(layout, NSMakeRange(NSMaxRange(visible), 5)).size(), 0u);
}

- (void)testHiddenCaretSitsBeforeTheToken {
    ATRDocument *document = [self documentWithParagraphs:@[kLongText] paragraphStyle:{}];
    ATRTextLayout *layout = [document layoutWithContainer:limitedContainer(120, 1) truncationToken:@"..."];
    NSUInteger end = NSMaxRange(layout.visibleRange);
    CGRect visibleEnd = [layout caretRectForPosition:upstream(end)];
    CGRect hidden = [layout caretRectForPosition:downstream(end + 10)];
    CGRect lastCharacter = selectionRects(layout, NSMakeRange(end - 1, 1)).back().rect;

    XCTAssertTrue(CGRectEqualToRect(visibleEnd, hidden));
    XCTAssertEqualWithAccuracy(CGRectGetMinX(visibleEnd), CGRectGetMaxX(lastCharacter), kTolerance);
    XCTAssertLessThan(CGRectGetMinX(visibleEnd), CGRectGetMaxX([layout lineAtIndex:0].frame) - 5);
}

- (void)testTheTokenMapsToNoCharacter {
    ATRDocument *document = [self documentWithParagraphs:@[kLongText] paragraphStyle:{}];
    ATRTextLayout *layout = [document layoutWithContainer:limitedContainer(120, 1) truncationToken:@"MORE"];
    ATRLineInfo line = [layout lineAtIndex:0];
    NSUInteger end = NSMaxRange(layout.visibleRange);
    CGPoint onToken = CGPointMake(CGRectGetMaxX(line.frame) - 3, CGRectGetMidY(line.frame));

    XCTAssertEqual([layout characterIndexAtPoint:onToken], NSNotFound);

    ATRTextPosition position = [layout closestPositionToPoint:onToken];
    XCTAssertEqual(position.offset, end);
    XCTAssertEqual(position.affinity, ATRTextAffinityUpstream);
}

- (void)testTruncatedParagraphEndKeepsItsText {
    // The first paragraph fits, but the second is cut by the line limit, so
    // the token follows the first paragraph's own text.
    ATRDocument *document = [self documentWithParagraphs:@[@"Fits", @"Cut"] paragraphStyle:{}];
    ATRTextLayout *layout = [document layoutWithContainer:limitedContainer(300, 1) truncationToken:nil];

    XCTAssertTrue(layout.truncated);
    XCTAssertTrue(NSEqualRanges(layout.visibleRange, NSMakeRange(0, 4)));
    XCTAssertTrue(NSEqualRanges([layout rangeOfLineAtIndex:0], NSMakeRange(0, 4)));
    XCTAssertEqual(selectionRects(layout, NSMakeRange(0, 4)).size(), 1u);
}

- (void)testTruncatedEmptyParagraphShowsNoText {
    ATRDocument *document = [self documentWithParagraphs:@[@"", @"Cut"] paragraphStyle:{}];
    ATRTextLayout *layout = [document layoutWithContainer:limitedContainer(300, 1) truncationToken:nil];

    XCTAssertTrue(layout.truncated);
    XCTAssertTrue(NSEqualRanges(layout.visibleRange, NSMakeRange(0, 0)));
    XCTAssertEqual(selectionRects(layout, NSMakeRange(0, layout.textLength)).size(), 0u);
    XCTAssertEqual([layout closestPositionToPoint:CGPointMake(100, 5)].offset, 0u);
}

- (void)testMaxHeightCutsWholeLines {
    ATRDocument *document = [self documentWithParagraphs:@[kLongText, kLongText] paragraphStyle:{}];
    ATRTextLayout *full = [document layoutWithContainer:container(120) truncationToken:nil];
    double twoLines = CGRectGetMaxY([full lineAtIndex:1].frame);
    ATRTextLayout *layout = [document layoutWithContainer:{120, twoLines + 1, 0, ATRLineHeightModeTypographic}
                                          truncationToken:nil];

    XCTAssertEqual(layout.lineCount, 2u);
    XCTAssertEqual(NSMaxRange(layout.visibleRange), NSMaxRange([layout rangeOfLineAtIndex:1]));
    XCTAssertLessThan(NSMaxRange(layout.visibleRange), layout.textLength);
}

// MARK: Granularity

- (void)testCharacterGranularity {
    NSString *family = @"\U0001F468‍\U0001F469‍\U0001F467";
    NSString *text = [NSString stringWithFormat:@"é%@x", family];
    ATRTextLayout *layout = [self layoutOf:@[text, @"y"] width:400];
    NSUInteger separator = text.length;

    XCTAssertTrue(NSEqualRanges([layout rangeEnclosingIndex:1 granularity:ATRTextGranularityCharacter], NSMakeRange(0, 2)));
    XCTAssertTrue(NSEqualRanges([layout rangeEnclosingIndex:5 granularity:ATRTextGranularityCharacter], NSMakeRange(2, family.length)));
    XCTAssertTrue(NSEqualRanges([layout rangeEnclosingIndex:separator granularity:ATRTextGranularityCharacter], NSMakeRange(separator, 1)));
    XCTAssertTrue(NSEqualRanges([layout rangeEnclosingIndex:separator + 1 granularity:ATRTextGranularityCharacter], NSMakeRange(separator + 1, 1)));
    XCTAssertEqual([layout rangeEnclosingIndex:layout.textLength granularity:ATRTextGranularityCharacter].location, NSNotFound);
    XCTAssertEqual([layout rangeEnclosingIndex:layout.textLength + 1 granularity:ATRTextGranularityCharacter].location, NSNotFound);
}

- (void)testWordAndSentenceGranularity {
    NSString *text = @"Hello brave world. Second sentence here.";
    ATRTextLayout *layout = [self layoutOf:@[@"Intro", text] width:1000];
    NSUInteger start = 6;

    XCTAssertTrue(NSEqualRanges([layout rangeEnclosingIndex:start + 8 granularity:ATRTextGranularityWord], NSMakeRange(start + 6, 5)));
    XCTAssertTrue(NSEqualRanges([layout rangeEnclosingIndex:start granularity:ATRTextGranularityWord], NSMakeRange(start, 5)));
    // Whitespace between words is its own token.
    XCTAssertTrue(NSEqualRanges([layout rangeEnclosingIndex:start + 5 granularity:ATRTextGranularityWord], NSMakeRange(start + 5, 1)));

    NSRange first = [layout rangeEnclosingIndex:start + 3 granularity:ATRTextGranularitySentence];
    NSRange second = [layout rangeEnclosingIndex:start + 25 granularity:ATRTextGranularitySentence];
    XCTAssertEqual(first.location, start);
    XCTAssertEqual(second.location, start + 19);
    XCTAssertEqual(NSMaxRange(second), start + text.length);

    // Sentences never cross a paragraph.
    NSRange intro = [layout rangeEnclosingIndex:1 granularity:ATRTextGranularitySentence];
    XCTAssertTrue(NSEqualRanges(intro, NSMakeRange(0, 5)));
    XCTAssertEqual([layout rangeEnclosingIndex:5 granularity:ATRTextGranularityWord].location, NSNotFound);
}

- (void)testLineAndParagraphGranularity {
    ATRTextLayout *layout = [self layoutOf:@[kLongText, @"Tail"] width:120];
    NSRange second = [layout rangeOfLineAtIndex:1];

    XCTAssertTrue(NSEqualRanges([layout rangeEnclosingIndex:second.location + 1 granularity:ATRTextGranularityLine], second));
    XCTAssertTrue(NSEqualRanges([layout rangeEnclosingIndex:second.location granularity:ATRTextGranularityLine], second));
    XCTAssertTrue(NSEqualRanges(
        [layout rangeEnclosingIndex:3 granularity:ATRTextGranularityParagraph],
        NSMakeRange(0, kLongText.length)
    ));
    // The separator belongs to the paragraph it ends.
    XCTAssertTrue(NSEqualRanges(
        [layout rangeEnclosingIndex:kLongText.length granularity:ATRTextGranularityParagraph],
        NSMakeRange(0, kLongText.length)
    ));
    XCTAssertTrue(NSEqualRanges(
        [layout rangeEnclosingIndex:layout.textLength granularity:ATRTextGranularityParagraph],
        NSMakeRange(kLongText.length + 1, 4)
    ));
}

- (void)testLineGranularityIsNotFoundForHiddenText {
    ATRDocument *document = [self documentWithParagraphs:@[kLongText] paragraphStyle:{}];
    ATRTextLayout *layout = [document layoutWithContainer:limitedContainer(120, 1) truncationToken:nil];
    NSUInteger hidden = NSMaxRange(layout.visibleRange) + 3;

    XCTAssertEqual([layout rangeEnclosingIndex:hidden granularity:ATRTextGranularityLine].location, NSNotFound);
    XCTAssertTrue(NSEqualRanges(
        [layout rangeEnclosingIndex:hidden granularity:ATRTextGranularityParagraph],
        NSMakeRange(0, kLongText.length)
    ));
}

// MARK: Edge cases

- (void)testEmptyDocument {
    ATRDocument *document = [[[ATRDocumentBuilder alloc] init] finish];
    ATRTextLayout *layout = [document layoutWithContainer:container(300) truncationToken:nil];

    XCTAssertEqual(layout.textLength, 0u);
    XCTAssertEqual(layout.visibleRange.length, 0u);
    XCTAssertEqual([layout closestPositionToPoint:CGPointMake(10, 10)].offset, 0u);
    XCTAssertEqual([layout characterIndexAtPoint:CGPointMake(10, 10)], NSNotFound);
    XCTAssertEqual([layout lineIndexContainingPosition:downstream(0)], NSNotFound);
    XCTAssertTrue(CGRectEqualToRect([layout caretRectForPosition:downstream(0)], CGRectZero));
    XCTAssertEqual(selectionRects(layout, NSMakeRange(0, 10)).size(), 0u);
    XCTAssertEqual([layout rangeEnclosingIndex:0 granularity:ATRTextGranularityParagraph].location, NSNotFound);
}

- (void)testHugeRangesDoNotOverflow {
    ATRTextLayout *layout = [self layoutOf:@[@"Hello"] width:300];

    XCTAssertEqual(selectionRects(layout, NSMakeRange(1, NSUIntegerMax - 1)).size(), 1u);
    XCTAssertEqual(selectionRects(layout, NSMakeRange(NSUIntegerMax - 1, 1)).size(), 0u);
    XCTAssertEqual([layout rangeEnclosingIndex:NSUIntegerMax granularity:ATRTextGranularityCharacter].location, NSNotFound);
}

- (void)testIncrementalLayoutKeepsGeometry {
    ATRDocumentBuilder *builder = [[ATRDocumentBuilder alloc] init];
    int32_t font = [builder registerFont:[self font]];
    ATRAttachmentDescriptor adaptive = {};
    adaptive.sizeKind = ATRAttachmentSizeKindAdaptive;
    adaptive.fields = ATRAttachmentFieldMaxWidth;
    adaptive.maxWidth = 80;

    [builder beginParagraph:{} textStyle:fontStyle(font)];
    [builder appendText:kLongText];
    [builder endParagraph];
    [builder beginParagraph:{} textStyle:fontStyle(font)];
    uint32_t attachment = [builder appendAttachment:adaptive accessibilityLabel:nil];
    [builder appendText:@"Image"];
    [builder endParagraph];
    [builder beginParagraph:{} textStyle:fontStyle(font)];
    [builder appendText:kLongText];
    [builder endParagraph];
    ATRDocument *document = [builder finish];

    ATRTextLayout *before = [document layoutWithContainer:container(150) truncationToken:nil];
    CGSize loaded = CGSizeMake(40, 60);
    NSDictionary *sizes = @{@(attachment): [NSValue valueWithBytes:&loaded objCType:@encode(CGSize)]};
    ATRTextLayout *reused = [document layoutWithContainer:container(150)
                                          truncationToken:nil
                                   attachmentContentSizes:sizes
                                           previousLayout:before];
    ATRTextLayout *full = [document layoutWithContainer:container(150)
                                        truncationToken:nil
                                 attachmentContentSizes:sizes];

    XCTAssertEqual(reused.lineCount, full.lineCount);

    for (NSUInteger index = 0; index < full.lineCount; ++index) {
        XCTAssertTrue(NSEqualRanges([reused rangeOfLineAtIndex:index], [full rangeOfLineAtIndex:index]));
    }

    NSRange range = NSMakeRange(0, full.textLength);
    auto expected = selectionRects(full, range);
    auto actual = selectionRects(reused, range);
    XCTAssertEqual(actual.size(), expected.size());

    for (size_t index = 0; index < std::min(actual.size(), expected.size()); ++index) {
        XCTAssertTrue(CGRectEqualToRect(actual[index].rect, expected[index].rect));
    }
}

- (void)testQueriesRunOffTheMainThread {
    ATRTextLayout *layout = [self layoutOf:@[kLongText] width:120];
    XCTestExpectation *done = [self expectationWithDescription:@"background"];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        dispatch_apply(8, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^(size_t) {
            for (NSUInteger index = 0; index < layout.textLength; ++index) {
                CGRect caret = [layout caretRectForPosition:downstream(index)];
                (void)[layout closestPositionToPoint:CGPointMake(CGRectGetMinX(caret), CGRectGetMidY(caret))];
                (void)[layout rangeEnclosingIndex:index granularity:ATRTextGranularityWord];
            }
        });
        [done fulfill];
    });

    [self waitForExpectations:@[done] timeout:10];
}

@end
