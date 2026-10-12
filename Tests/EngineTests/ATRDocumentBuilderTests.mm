// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#import <XCTest/XCTest.h>

#import "ATRDocumentBuilder.h"

#include "atr/Document.hpp"

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

@end
