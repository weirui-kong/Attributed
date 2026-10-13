// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#import <XCTest/XCTest.h>

#import "ATRDocumentBuilder.h"

#include <set>
#include <string>

#include "atr/document/Document.hpp"

@interface ATRDocumentBuilderTests : XCTestCase
@end

@implementation ATRDocumentBuilderTests

- (void)testStructuralMisuseRaises {
    ATRDocumentBuilder *nested = [[ATRDocumentBuilder alloc] init];
    [nested beginParagraph:ATRParagraphStyle{} textStyle:ATRTextStyle{}];
    XCTAssertThrowsSpecificNamed(
        [nested beginParagraph:ATRParagraphStyle{} textStyle:ATRTextStyle{}],
        NSException,
        NSInternalInconsistencyException
    );

    ATRDocumentBuilder *outside = [[ATRDocumentBuilder alloc] init];
    XCTAssertThrowsSpecificNamed(
        [outside appendText:@"orphan"],
        NSException,
        NSInternalInconsistencyException
    );

    ATRDocumentBuilder *unclosed = [[ATRDocumentBuilder alloc] init];
    [unclosed pushSpan:ATRTextStyle{} interaction:ATRNoInteraction];
    XCTAssertThrowsSpecificNamed([unclosed finish], NSException, NSInternalInconsistencyException);
}

- (void)testScopesMustCloseInOrder {
    atr::DocumentBuilder builder;
    XCTAssertEqual(builder.beginParagraph({}, {}), atr::BuildStatus::Ok);
    XCTAssertEqual(builder.pushSpan({}, atr::kNoInteraction), atr::BuildStatus::Ok);
    XCTAssertEqual(builder.endParagraph(), atr::BuildStatus::MismatchedScope);
    XCTAssertEqual(builder.popSpan(), atr::BuildStatus::Ok);
    XCTAssertEqual(builder.endParagraph(), atr::BuildStatus::Ok);

    std::shared_ptr<const atr::Document> document;
    XCTAssertEqual(builder.finish(document), atr::BuildStatus::Ok);
    XCTAssertEqual(builder.finish(document), atr::BuildStatus::AlreadyFinished);
}

- (void)testDumpEscapesTextAndKeepsSurrogatePairs {
    ATRDocumentBuilder *builder = [[ATRDocumentBuilder alloc] init];
    [builder beginParagraph:ATRParagraphStyle{} textStyle:ATRTextStyle{}];
    [builder appendText:@"a\"b\\c\n\t😀"];
    [builder endParagraph];

    NSString *dump = [[builder finish] dump];
    NSString *ops = [dump componentsSeparatedByString:@"\n---"].firstObject;

    XCTAssertEqualObjects(
        ops,
        @"base paragraph{} text{fg=c0}\n"
        @"P paragraph{} text{}\n"
        @"  \"a\\\"b\\\\c\\n\\t😀\"\n"
        @"/P"
    );
}

- (void)testEqualGradientsAreDeduplicated {
    ATRDocumentBuilder *builder = [[ATRDocumentBuilder alloc] init];
    int32_t colors[] = {0, 0};
    double locations[] = {0, 1};
    ATRGradientDescriptor descriptor = {0, 0.5, 1, 0.5, ATRGradientScopeParagraph};

    int32_t first = [builder registerGradientWithColors:colors
                                              locations:nil
                                                  count:2
                                             descriptor:descriptor];
    int32_t same = [builder registerGradientWithColors:colors
                                             locations:nil
                                                 count:2
                                            descriptor:descriptor];
    int32_t withLocations = [builder registerGradientWithColors:colors
                                                      locations:locations
                                                          count:2
                                                     descriptor:descriptor];
    descriptor.scope = ATRGradientScopeLine;
    int32_t otherScope = [builder registerGradientWithColors:colors
                                                   locations:nil
                                                       count:2
                                                  descriptor:descriptor];

    XCTAssertEqual(first, 0);
    XCTAssertEqual(same, 0);
    XCTAssertEqual(withLocations, 1);
    XCTAssertEqual(otherScope, 2);
}

- (void)testFormatNumberUsesShortestRoundTrip {
    XCTAssertEqual(atr::formatNumber(4), "4");
    XCTAssertEqual(atr::formatNumber(-2), "-2");
    XCTAssertEqual(atr::formatNumber(1.5), "1.5");
    XCTAssertEqual(atr::formatNumber(0.1), "0.1");
    XCTAssertEqual(atr::formatNumber(1.0 / 3.0), "0.3333333333333333");
}

- (void)testEveryStatusAfterFinishingIsAlreadyFinished {
    atr::DocumentBuilder builder;
    std::shared_ptr<const atr::Document> document;
    XCTAssertEqual(builder.finish(document), atr::BuildStatus::Ok);
    uint32_t attachment = 0;

    XCTAssertEqual(builder.beginParagraph({}, {}), atr::BuildStatus::AlreadyFinished);
    XCTAssertEqual(builder.endParagraph(), atr::BuildStatus::AlreadyFinished);
    XCTAssertEqual(builder.pushSpan({}, atr::kNoInteraction), atr::BuildStatus::AlreadyFinished);
    XCTAssertEqual(builder.popSpan(), atr::BuildStatus::AlreadyFinished);
    XCTAssertEqual(builder.appendText(u"a", 1), atr::BuildStatus::AlreadyFinished);
    XCTAssertEqual(builder.appendAttachment({}, attachment), atr::BuildStatus::AlreadyFinished);
    XCTAssertEqual(builder.registerGradient({}), -1);
    XCTAssertEqual(builder.registerInteraction({}), atr::kNoInteraction);
    // Setting a base style after finishing is ignored rather than crashing.
    builder.setBaseTextStyle({});
}

- (void)testMisplacedContentAndScopes {
    atr::DocumentBuilder builder;
    uint32_t attachment = 0;

    XCTAssertEqual(builder.appendText(u"a", 1), atr::BuildStatus::ContentOutsideParagraph);
    XCTAssertEqual(builder.appendAttachment({}, attachment), atr::BuildStatus::ContentOutsideParagraph);
    XCTAssertEqual(builder.endParagraph(), atr::BuildStatus::MismatchedScope);
    XCTAssertEqual(builder.popSpan(), atr::BuildStatus::MismatchedScope);
    XCTAssertEqual(builder.pushSpan({}, 0), atr::BuildStatus::UnknownInteraction);

    // A span outside paragraphs may hold whole paragraphs, but content still
    // needs a paragraph.
    XCTAssertEqual(builder.pushSpan({}, atr::kNoInteraction), atr::BuildStatus::Ok);
    XCTAssertEqual(builder.appendText(u"a", 1), atr::BuildStatus::ContentOutsideParagraph);
    XCTAssertEqual(builder.beginParagraph({}, {}), atr::BuildStatus::Ok);
    XCTAssertEqual(builder.beginParagraph({}, {}), atr::BuildStatus::NestedParagraph);
    XCTAssertEqual(builder.popSpan(), atr::BuildStatus::MismatchedScope);
    XCTAssertEqual(builder.endParagraph(), atr::BuildStatus::Ok);

    std::shared_ptr<const atr::Document> document;
    XCTAssertEqual(builder.finish(document), atr::BuildStatus::UnclosedScope);
    XCTAssertEqual(builder.popSpan(), atr::BuildStatus::Ok);
    XCTAssertEqual(builder.finish(document), atr::BuildStatus::Ok);
    XCTAssertTrue(document != nullptr);
}

- (void)testStatusesHaveDistinctDescriptions {
    std::set<std::string> descriptions;

    for (auto status : {
             atr::BuildStatus::Ok,
             atr::BuildStatus::NestedParagraph,
             atr::BuildStatus::ContentOutsideParagraph,
             atr::BuildStatus::MismatchedScope,
             atr::BuildStatus::UnknownInteraction,
             atr::BuildStatus::UnclosedScope,
             atr::BuildStatus::AlreadyFinished,
         }) {
        const char *description = atr::describe(status);
        XCTAssertTrue(description != nullptr);
        descriptions.insert(description);
    }

    XCTAssertEqual(descriptions.size(), 7u);
}

- (void)testEmptyTextEmitsNoOp {
    atr::DocumentBuilder builder;
    builder.beginParagraph({}, {});
    XCTAssertEqual(builder.appendText(u"", 0), atr::BuildStatus::Ok);
    builder.endParagraph();
    std::shared_ptr<const atr::Document> document;
    builder.finish(document);

    XCTAssertEqual(document->ops().size(), 2u);
    XCTAssertTrue(document->text().empty());
}

- (void)testTextIsPooledInOrder {
    atr::DocumentBuilder builder;
    builder.beginParagraph({}, {});
    builder.appendText(u"ab", 2);
    builder.appendText(u"cd", 2);
    builder.endParagraph();
    std::shared_ptr<const atr::Document> document;
    builder.finish(document);

    XCTAssertTrue(document->text() == u"abcd");
    const atr::Op &second = document->ops()[2];
    XCTAssertEqual(second.kind, atr::OpKind::Text);
    XCTAssertEqual(second.first, 2u);
    XCTAssertEqual(second.second, 2u);
}

- (void)testResourcesAreDeduplicatedByEquality {
    ATRDocumentBuilder *builder = [[ATRDocumentBuilder alloc] init];
    ATRPlatformFont *font = [ATRPlatformFont systemFontOfSize:14];

    int32_t first = [builder registerFont:font];
    int32_t same = [builder registerFont:[ATRPlatformFont systemFontOfSize:14]];
    int32_t bigger = [builder registerFont:[ATRPlatformFont systemFontOfSize:15]];
    int32_t bold = [builder registerFont:[ATRPlatformFont boldSystemFontOfSize:14]];

    XCTAssertEqual(first, 0);
    XCTAssertEqual(same, 0);
    XCTAssertEqual(bigger, 1);
    XCTAssertEqual(bold, 2);

    // Color 0 is the label color registered by the builder itself.
    int32_t red = [builder registerColor:[ATRPlatformColor colorWithRed:1 green:0 blue:0 alpha:1]];
    int32_t sameRed = [builder registerColor:[ATRPlatformColor colorWithRed:1 green:0 blue:0 alpha:1]];
    int32_t translucent = [builder registerColor:[ATRPlatformColor colorWithRed:1 green:0 blue:0 alpha:0.5]];
#if TARGET_OS_OSX
    int32_t label = [builder registerColor:NSColor.labelColor];
#else
    int32_t label = [builder registerColor:UIColor.labelColor];
#endif

    XCTAssertEqual(red, 1);
    XCTAssertEqual(sameRed, 1);
    XCTAssertEqual(translucent, 2);
    XCTAssertEqual(label, 0);

    [builder beginParagraph:ATRParagraphStyle{} textStyle:ATRTextStyle{}];
    [builder endParagraph];
    ATRDocument *document = [builder finish];
    XCTAssertEqual(document.fontCount, 3u);
    XCTAssertEqual(document.colorCount, 3u);
    XCTAssertEqualObjects([document fontAtIndex:1], [ATRPlatformFont systemFontOfSize:15]);
}

- (void)testGradientsDifferByEveryField {
    ATRDocumentBuilder *builder = [[ATRDocumentBuilder alloc] init];
    int32_t twoColors[] = {0, 1};
    int32_t reversed[] = {1, 0};
    double locations[] = {0, 1};
    double shifted[] = {0.2, 1};
    ATRGradientDescriptor base = {0, 0.5, 1, 0.5, ATRGradientScopeParagraph};
    ATRGradientDescriptor vertical = {0.5, 0, 0.5, 1, ATRGradientScopeParagraph};

    int32_t first = [builder registerGradientWithColors:twoColors locations:locations count:2 descriptor:base];
    XCTAssertEqual([builder registerGradientWithColors:reversed locations:locations count:2 descriptor:base], first + 1);
    XCTAssertEqual([builder registerGradientWithColors:twoColors locations:shifted count:2 descriptor:base], first + 2);
    XCTAssertEqual([builder registerGradientWithColors:twoColors locations:locations count:2 descriptor:vertical], first + 3);
    XCTAssertEqual([builder registerGradientWithColors:twoColors locations:locations count:1 descriptor:base], first + 4);
    XCTAssertEqual([builder registerGradientWithColors:twoColors locations:locations count:2 descriptor:base], first);

    XCTAssertThrowsSpecificNamed(
        [builder registerGradientWithColors:twoColors locations:nil count:0 descriptor:base],
        NSException,
        NSInvalidArgumentException
    );

    [builder beginParagraph:ATRParagraphStyle{} textStyle:ATRTextStyle{}];
    [builder endParagraph];
    XCTAssertEqual([builder finish].gradientCount, 5u);
}

- (void)testInteractionsAndAttachmentsGetSequentialIDs {
    ATRDocumentBuilder *builder = [[ATRDocumentBuilder alloc] init];
    ATRGesture tap = {};
    tap.kind = ATRGestureKindTap;
    tap.tapCount = 2;
    ATRGesture press = {};
    press.kind = ATRGestureKindLongPress;
    press.minimumPressDuration = 1.25;

    XCTAssertEqual([builder registerInteractionWithGesture:tap], 0u);
    XCTAssertEqual([builder registerInteractionWithGesture:press], 1u);
    // Equal gestures are separate interactions; they carry separate values.
    XCTAssertEqual([builder registerInteractionWithGesture:tap], 2u);

    ATRAttachmentDescriptor descriptor = {};
    descriptor.sizeKind = ATRAttachmentSizeKindFixed;
    descriptor.width = 10;
    descriptor.height = 20;
    descriptor.alignmentKind = ATRAttachmentAlignmentKindOffset;
    descriptor.alignmentOffset = -3;

    [builder beginParagraph:ATRParagraphStyle{} textStyle:ATRTextStyle{}];
    XCTAssertEqual([builder appendAttachment:descriptor accessibilityLabel:@"first"], 0u);
    XCTAssertEqual([builder appendAttachment:descriptor accessibilityLabel:@""], 1u);
    [builder endParagraph];
    ATRDocument *document = [builder finish];

    XCTAssertEqual(document.interactionCount, 3u);
    XCTAssertEqual([document gestureForInteraction:0].tapCount, 2u);
    XCTAssertEqual([document gestureForInteraction:1].kind, ATRGestureKindLongPress);
    XCTAssertEqual([document gestureForInteraction:1].minimumPressDuration, 1.25);
    XCTAssertEqual(document.attachmentCount, 2u);

    ATRAttachmentDescriptor stored = [document attachmentDescriptorAtIndex:0];
    XCTAssertEqual(stored.width, 10);
    XCTAssertEqual(stored.height, 20);
    XCTAssertEqual(stored.alignmentKind, ATRAttachmentAlignmentKindOffset);
    XCTAssertEqual(stored.alignmentOffset, -3);
    // An empty accessibility label counts as none.
    XCTAssertEqualObjects(document.plainText, @"first");
}

- (void)testPlainTextJoinsParagraphsAndLabelsAttachments {
    ATRDocumentBuilder *builder = [[ATRDocumentBuilder alloc] init];
    ATRAttachmentDescriptor descriptor = {};
    descriptor.sizeKind = ATRAttachmentSizeKindFixed;
    descriptor.width = 4;
    descriptor.height = 4;

    [builder beginParagraph:ATRParagraphStyle{} textStyle:ATRTextStyle{}];
    [builder appendText:@"Hi "];
    [builder appendAttachment:descriptor accessibilityLabel:@"wave"];
    [builder appendAttachment:descriptor accessibilityLabel:nil];
    [builder appendText:@"!"];
    [builder endParagraph];
    [builder beginParagraph:ATRParagraphStyle{} textStyle:ATRTextStyle{}];
    [builder endParagraph];
    [builder beginParagraph:ATRParagraphStyle{} textStyle:ATRTextStyle{}];
    [builder appendText:@"End"];
    [builder endParagraph];
    ATRDocument *document = [builder finish];

    XCTAssertEqualObjects(document.plainText, @"Hi wave!\n\nEnd");
    // The index space keeps one U+FFFC per attachment instead.
    XCTAssertEqualObjects([document textInRange:NSMakeRange(0, 6)], @"Hi ￼￼!");
}

- (void)testUnknownInteractionRaises {
    ATRDocumentBuilder *builder = [[ATRDocumentBuilder alloc] init];
    XCTAssertThrowsSpecificNamed(
        [builder pushSpan:ATRTextStyle{} interaction:3],
        NSException,
        NSInternalInconsistencyException
    );

    ATRDocumentBuilder *finished = [[ATRDocumentBuilder alloc] init];
    [finished finish];
    XCTAssertThrowsSpecificNamed([finished finish], NSException, NSInternalInconsistencyException);
    XCTAssertThrowsSpecificNamed(
        [finished registerInteractionWithGesture:ATRGesture{}],
        NSException,
        NSInternalInconsistencyException
    );
}

- (void)testEmptyDocumentLaysOutToNothing {
    ATRDocument *document = [[[ATRDocumentBuilder alloc] init] finish];
    ATRTextLayout *layout = [document layoutWithContainer:{300, INFINITY, 0, ATRLineHeightModeTypographic}
                                          truncationToken:nil];

    XCTAssertEqual(layout.lineCount, 0u);
    XCTAssertTrue(CGSizeEqualToSize(layout.size, CGSizeZero));
    XCTAssertFalse(layout.truncated);
    XCTAssertEqualObjects(document.plainText, @"");
}

@end
