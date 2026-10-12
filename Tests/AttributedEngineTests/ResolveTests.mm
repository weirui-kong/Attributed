// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#import <XCTest/XCTest.h>

#include "atr/resolve/Resolve.hpp"

@interface ResolveTests : XCTestCase
@end

@implementation ResolveTests

- (void)testInheritanceRunMergingAndInteractions {
    atr::DocumentBuilder builder;
    atr::TextStyle base;
    base.foreground = atr::Fill{atr::FillKind::Color, 0};
    builder.setBaseTextStyle(base);

    atr::TextStyle bold;
    bold.font = 1;
    atr::TextStyle underlined;
    underlined.underline = atr::Underline{};
    atr::TextStyle gradient;
    gradient.foreground = atr::Fill{atr::FillKind::Gradient, 0};

    atr::ParagraphStyle spaced;
    spaced.lineSpacing = 4;
    atr::TextStyle paragraphFont;
    paragraphFont.font = 0;

    // Interaction 7 is a long press and 9 a tap, so a run nested in both
    // keeps both; a nested tap inside another tap keeps only the inner one.
    for (uint32_t index = 0; index < 10; ++index) {
        atr::Gesture gesture;
        gesture.kind = index == 7 ? atr::GestureKind::LongPress : atr::GestureKind::Tap;
        builder.registerInteraction(gesture);
    }

    XCTAssertEqual(builder.pushSpan({}, 10), atr::BuildStatus::UnknownInteraction);
    XCTAssertEqual(builder.pushSpan({}, 7), atr::BuildStatus::Ok);
    builder.beginParagraph(spaced, paragraphFont);
    builder.appendText(u"Hello ", 6);
    builder.pushSpan(bold, atr::kNoInteraction);
    builder.appendText(u"Wor", 3);
    builder.popSpan();
    builder.pushSpan(bold, atr::kNoInteraction);
    builder.appendText(u"ld", 2);
    builder.popSpan();
    builder.pushSpan(gradient, 9);
    builder.pushSpan(underlined, atr::kNoInteraction);
    builder.appendText(u"!", 1);
    uint32_t attachment = 0;
    builder.appendAttachment({}, attachment);
    builder.popSpan();
    builder.popSpan();
    builder.endParagraph();
    builder.popSpan();

    builder.beginParagraph({}, {});
    builder.appendText(u"שלום", 4);
    builder.endParagraph();

    builder.beginParagraph({}, {});
    builder.endParagraph();

    std::shared_ptr<const atr::Document> document;
    XCTAssertEqual(builder.finish(document), atr::BuildStatus::Ok);

    atr::ResolvedDocument resolved = atr::resolve(*document);
    std::string dump = resolved.dump();

    // Interaction 7 wraps the first paragraph; 9 wraps "!" and the
    // attachment.
    XCTAssertEqual(resolved.interactionRanges[7], std::make_pair(0u, 13u));
    XCTAssertEqual(resolved.interactionRanges[9], std::make_pair(11u, 2u));
    XCTAssertTrue(resolved.text(14, 4) == u"\u05E9\u05DC\u05D5\u05DD");
    XCTAssertEqual(
        dump,
        "s0 = font=f0 fg=c0 i=[7]\n"
        "s1 = font=f1 fg=c0 i=[7]\n"
        "s2 = font=f0 fg=g0 underline=single,solid underlineFill=g0 i=[9,7]\n"
        "s3 = font=default fg=c0\n"
        "P0 align=natural direction=leftToRight lineSpacing=4 paragraphSpacing=0 s0\n"
        "  [0,6) s0 \"Hello \"\n"
        "  [6,5) s1 \"World\"\n"
        "  [11,1) s2 \"!\"\n"
        "  [12,1) s2 a0\n"
        "P1 align=natural direction=rightToLeft lineSpacing=0 paragraphSpacing=0 s3\n"
        "  [0,4) s3 \"שלום\"\n"
        "P2 align=natural direction=leftToRight lineSpacing=0 paragraphSpacing=0 s3",
        "%s",
        dump.c_str()
    );
}

@end
