// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#import <XCTest/XCTest.h>

#include "atr/resolve/Resolve.hpp"

namespace {

std::u16string text(const char16_t *value) {
    return value;
}

void append(atr::DocumentBuilder &builder, const std::u16string &value) {
    builder.appendText(value.data(), value.size());
}

void paragraph(atr::DocumentBuilder &builder, const std::u16string &value, atr::ParagraphStyle style = {}) {
    builder.beginParagraph(style, {});
    append(builder, value);
    builder.endParagraph();
}

atr::ResolvedDocument resolve(atr::DocumentBuilder &builder) {
    std::shared_ptr<const atr::Document> document;
    atr::BuildStatus status = builder.finish(document);
    NSCAssert(status == atr::BuildStatus::Ok, @"%s", atr::describe(status));
    return atr::resolve(*document);
}

atr::Gesture tap(uint32_t count = 1) {
    atr::Gesture gesture;
    gesture.tapCount = count;
    return gesture;
}

atr::Gesture longPress() {
    atr::Gesture gesture;
    gesture.kind = atr::GestureKind::LongPress;
    return gesture;
}

} // namespace

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

// MARK: Writing direction

- (void)testNaturalDirectionFollowsTheFirstStrongCharacter {
    atr::DocumentBuilder builder;
    // Digits, punctuation, and spaces are neutral; the first strong letter
    // decides.
    paragraph(builder, u"123, שלום abc");
    paragraph(builder, u"  abc שלום");
    paragraph(builder, u"مرحبا");
    paragraph(builder, u"123 !?");
    paragraph(builder, u"");
    paragraph(builder, u"中文");
    paragraph(builder, u"Αβγ");
    // A supplementary right-to-left letter (Adlam) decodes as a pair.
    paragraph(builder, u"\U0001E900");
    // Emoji are neutral.
    paragraph(builder, u"\U0001F600 א");
    // Multiplication and division signs sit inside the Latin range but are
    // neutral.
    paragraph(builder, u"×÷ א");
    atr::ResolvedDocument resolved = resolve(builder);

    using atr::WritingDirection;
    std::vector<WritingDirection> expected = {
        WritingDirection::RightToLeft,
        WritingDirection::LeftToRight,
        WritingDirection::RightToLeft,
        WritingDirection::LeftToRight,
        WritingDirection::LeftToRight,
        WritingDirection::LeftToRight,
        WritingDirection::LeftToRight,
        WritingDirection::RightToLeft,
        WritingDirection::RightToLeft,
        WritingDirection::RightToLeft,
    };
    XCTAssertEqual(resolved.paragraphs.size(), expected.size());

    for (size_t index = 0; index < expected.size(); ++index) {
        XCTAssertEqual(resolved.paragraphs[index].style.direction, expected[index], @"paragraph %zu", index);
    }
}

- (void)testExplicitDirectionWinsOverContent {
    atr::DocumentBuilder builder;
    atr::ParagraphStyle leftToRight;
    leftToRight.writingDirection = atr::WritingDirection::LeftToRight;
    atr::ParagraphStyle rightToLeft;
    rightToLeft.writingDirection = atr::WritingDirection::RightToLeft;
    paragraph(builder, u"שלום", leftToRight);
    paragraph(builder, u"abc", rightToLeft);
    atr::ResolvedDocument resolved = resolve(builder);

    XCTAssertEqual(resolved.paragraphs[0].style.direction, atr::WritingDirection::LeftToRight);
    XCTAssertEqual(resolved.paragraphs[1].style.direction, atr::WritingDirection::RightToLeft);
}

// MARK: Inheritance

- (void)testParagraphStylesFallBackToDefaults {
    atr::DocumentBuilder builder;
    atr::ParagraphStyle partial;
    partial.alignment = atr::TextAlignment::Center;
    paragraph(builder, u"a", partial);
    paragraph(builder, u"b");
    atr::ResolvedDocument resolved = resolve(builder);

    XCTAssertEqual(resolved.paragraphs[0].style.alignment, atr::TextAlignment::Center);
    XCTAssertEqual(resolved.paragraphs[0].style.lineSpacing, 0);
    XCTAssertEqual(resolved.paragraphs[0].style.paragraphSpacing, 0);
    // Paragraph styles never leak into the next paragraph.
    XCTAssertEqual(resolved.paragraphs[1].style.alignment, atr::TextAlignment::Natural);
}

- (void)testNestedSpansOverrideOnlyTheirFields {
    atr::DocumentBuilder builder;
    atr::TextStyle outer;
    outer.font = 2;
    outer.kern = 1.5;
    outer.backgroundColor = 4;
    atr::TextStyle inner;
    inner.kern = 3;
    inner.baselineOffset = -2;

    builder.beginParagraph({}, {});
    builder.pushSpan(outer, atr::kNoInteraction);
    append(builder, u"a");
    builder.pushSpan(inner, atr::kNoInteraction);
    append(builder, u"b");
    builder.popSpan();
    append(builder, u"c");
    builder.popSpan();
    append(builder, u"d");
    builder.endParagraph();
    atr::ResolvedDocument resolved = resolve(builder);

    const auto &runs = resolved.paragraphs[0].runs;
    XCTAssertEqual(runs.size(), 4u);
    const atr::ResolvedTextStyle &a = resolved.styles[runs[0].style];
    const atr::ResolvedTextStyle &b = resolved.styles[runs[1].style];
    const atr::ResolvedTextStyle &d = resolved.styles[runs[3].style];

    XCTAssertEqual(a.font, 2);
    XCTAssertEqual(a.kern, 1.5);
    XCTAssertEqual(b.font, 2);
    XCTAssertEqual(b.kern, 3);
    XCTAssertEqual(b.baselineOffset, -2);
    XCTAssertEqual(b.backgroundColor, std::optional<int32_t>(4));
    // "c" returns to the outer style and shares its index.
    XCTAssertEqual(runs[2].style, runs[0].style);
    XCTAssertEqual(d.font, atr::kDefaultFont);
    XCTAssertEqual(d.kern, 0);
    XCTAssertFalse(d.backgroundColor.has_value());
}

- (void)testEqualStylesShareAnIndexAndRunsMerge {
    atr::DocumentBuilder builder;
    atr::TextStyle red;
    red.foreground = atr::Fill{atr::FillKind::Color, 3};

    builder.beginParagraph({}, {});
    builder.pushSpan(red, atr::kNoInteraction);
    append(builder, u"ab");
    builder.popSpan();
    builder.pushSpan(red, atr::kNoInteraction);
    append(builder, u"cd");
    builder.popSpan();
    builder.endParagraph();
    builder.beginParagraph({}, red);
    append(builder, u"ef");
    builder.endParagraph();
    atr::ResolvedDocument resolved = resolve(builder);

    XCTAssertEqual(resolved.paragraphs[0].runs.size(), 1u);
    XCTAssertEqual(resolved.paragraphs[0].runs[0].length, 4u);
    XCTAssertEqual(resolved.paragraphs[0].runs[0].style, resolved.paragraphs[1].runs[0].style);
}

- (void)testAttachmentsAreAlwaysTheirOwnRun {
    atr::DocumentBuilder builder;
    uint32_t first = 0;
    uint32_t second = 0;
    builder.beginParagraph({}, {});
    append(builder, u"a");
    builder.appendAttachment({}, first);
    builder.appendAttachment({}, second);
    append(builder, u"b");
    builder.endParagraph();
    atr::ResolvedDocument resolved = resolve(builder);

    const auto &runs = resolved.paragraphs[0].runs;
    XCTAssertEqual(runs.size(), 4u);
    XCTAssertEqual(runs[1].attachment, std::optional<uint32_t>(first));
    XCTAssertEqual(runs[2].attachment, std::optional<uint32_t>(second));
    XCTAssertEqual(runs[1].length, 1u);
    // Text after an attachment never merges into it.
    XCTAssertFalse(runs[3].attachment.has_value());
    XCTAssertTrue(resolved.paragraphs[0].text == u"a￼￼b");
}

- (void)testUnderlineFillFollowsTheForegroundUnlessSet {
    atr::DocumentBuilder builder;
    atr::TextStyle base;
    base.foreground = atr::Fill{atr::FillKind::Color, 1};
    base.underline = atr::Underline{};
    builder.setBaseTextStyle(base);
    atr::TextStyle gradient;
    gradient.foreground = atr::Fill{atr::FillKind::Gradient, 0};
    atr::TextStyle ownFill;
    ownFill.underlineFill = atr::Fill{atr::FillKind::Color, 5};
    atr::TextStyle fillOnly;
    fillOnly.underline = std::nullopt;

    builder.beginParagraph({}, {});
    append(builder, u"a");
    builder.pushSpan(gradient, atr::kNoInteraction);
    append(builder, u"b");
    builder.pushSpan(ownFill, atr::kNoInteraction);
    append(builder, u"c");
    builder.popSpan();
    builder.popSpan();
    builder.endParagraph();
    atr::ResolvedDocument resolved = resolve(builder);

    const auto &runs = resolved.paragraphs[0].runs;
    XCTAssertTrue(resolved.styles[runs[0].style].underlineFill == (atr::Fill{atr::FillKind::Color, 1}));
    XCTAssertTrue(resolved.styles[runs[1].style].underlineFill == (atr::Fill{atr::FillKind::Gradient, 0}));
    XCTAssertTrue(resolved.styles[runs[2].style].underlineFill == (atr::Fill{atr::FillKind::Color, 5}));
}

- (void)testUnderlineFillWithoutAnUnderlineIsIgnored {
    atr::DocumentBuilder builder;
    atr::TextStyle fillOnly;
    fillOnly.underlineFill = atr::Fill{atr::FillKind::Color, 5};
    builder.beginParagraph({}, fillOnly);
    append(builder, u"a");
    builder.endParagraph();
    atr::ResolvedDocument resolved = resolve(builder);

    const atr::ResolvedTextStyle &style = resolved.styles[resolved.paragraphs[0].runs[0].style];
    XCTAssertFalse(style.underline.has_value());
    XCTAssertFalse(style.underlineFill.has_value());
}

- (void)testEmptyParagraphKeepsItsTextStyle {
    atr::DocumentBuilder builder;
    atr::TextStyle big;
    big.font = 7;
    builder.beginParagraph({}, big);
    builder.endParagraph();
    atr::ResolvedDocument resolved = resolve(builder);

    XCTAssertTrue(resolved.paragraphs[0].runs.empty());
    XCTAssertEqual(resolved.styles[resolved.paragraphs[0].paragraphTextStyle].font, 7);
}

// MARK: Interactions

- (void)testInteractionSetsKeepTheInnermostPerGestureKey {
    atr::DocumentBuilder builder;
    uint32_t outerTap = builder.registerInteraction(tap());
    uint32_t innerTap = builder.registerInteraction(tap());
    uint32_t doubleTap = builder.registerInteraction(tap(2));
    uint32_t press = builder.registerInteraction(longPress());

    builder.beginParagraph({}, {});
    builder.pushSpan({}, outerTap);
    append(builder, u"a");
    builder.pushSpan({}, doubleTap);
    builder.pushSpan({}, press);
    builder.pushSpan({}, innerTap);
    append(builder, u"b");
    builder.popSpan();
    append(builder, u"c");
    builder.popSpan();
    builder.popSpan();
    builder.popSpan();
    append(builder, u"d");
    builder.endParagraph();
    atr::ResolvedDocument resolved = resolve(builder);

    const auto &runs = resolved.paragraphs[0].runs;
    XCTAssertEqual(runs.size(), 4u);
    auto setOf = [&](size_t run) {
        uint32_t set = resolved.styles[runs[run].style].interactionSet;
        return set == atr::kNoInteractionSet ? std::vector<uint32_t>{} : resolved.interactionSets[set];
    };

    XCTAssertTrue(setOf(0) == std::vector<uint32_t>({outerTap}));
    // The inner tap replaces the outer one; the double tap and long press
    // have their own keys and stay.
    XCTAssertTrue(setOf(1) == std::vector<uint32_t>({innerTap, press, doubleTap}));
    XCTAssertTrue(setOf(2) == std::vector<uint32_t>({press, doubleTap, outerTap}));
    XCTAssertTrue(setOf(3).empty());
}

- (void)testEqualInteractionSetsShareAnIndex {
    atr::DocumentBuilder builder;
    uint32_t link = builder.registerInteraction(tap());
    builder.beginParagraph({}, {});
    builder.pushSpan({}, link);
    append(builder, u"a");
    builder.popSpan();
    builder.endParagraph();
    builder.beginParagraph({}, {});
    builder.pushSpan({}, link);
    append(builder, u"b");
    builder.popSpan();
    builder.endParagraph();
    atr::ResolvedDocument resolved = resolve(builder);

    XCTAssertEqual(resolved.interactionSets.size(), 1u);
}

- (void)testInteractionRangesSpanParagraphsAndSkipOuterSeparators {
    atr::DocumentBuilder builder;
    uint32_t wrapper = builder.registerInteraction(tap());
    uint32_t empty = builder.registerInteraction(tap(2));
    uint32_t unused = builder.registerInteraction(longPress());

    paragraph(builder, u"Intro");
    // A span around whole paragraphs starts after the separator before its
    // first paragraph and ends before the separator after its last one.
    builder.pushSpan({}, wrapper);
    paragraph(builder, u"One");
    paragraph(builder, u"Two");
    builder.popSpan();
    paragraph(builder, u"Outro");

    builder.beginParagraph({}, {});
    builder.pushSpan({}, empty);
    builder.popSpan();
    append(builder, u"x");
    builder.endParagraph();
    atr::ResolvedDocument resolved = resolve(builder);

    XCTAssertEqual(resolved.interactionRanges[wrapper], std::make_pair(6u, 7u));
    XCTAssertTrue(resolved.text(6, 7) == u"One\nTwo");
    XCTAssertEqual(resolved.interactionRanges[empty], std::make_pair(20u, 0u));
    XCTAssertEqual(resolved.interactionRanges[unused], std::make_pair(0u, 0u));
}

- (void)testSpanAroundTheFirstParagraphStartsAtZero {
    atr::DocumentBuilder builder;
    uint32_t wrapper = builder.registerInteraction(tap());
    builder.pushSpan({}, wrapper);
    paragraph(builder, u"Only");
    builder.popSpan();
    atr::ResolvedDocument resolved = resolve(builder);

    XCTAssertEqual(resolved.interactionRanges[wrapper], std::make_pair(0u, 4u));
}

// MARK: Text

- (void)testParagraphStartsAndTextRanges {
    atr::DocumentBuilder builder;
    paragraph(builder, u"ab");
    paragraph(builder, u"");
    paragraph(builder, u"\U0001F600c");
    atr::ResolvedDocument resolved = resolve(builder);

    XCTAssertEqual(resolved.paragraphs[0].start, 0u);
    XCTAssertEqual(resolved.paragraphs[1].start, 3u);
    XCTAssertEqual(resolved.paragraphs[2].start, 4u);
    XCTAssertEqual(resolved.length(), 7u);
    XCTAssertTrue(resolved.text(0, 7) == u"ab\n\n\U0001F600c");
    XCTAssertTrue(resolved.text(2, 2) == u"\n\n");
    XCTAssertTrue(resolved.text(4, 2) == u"\U0001F600");
    XCTAssertTrue(resolved.text(6, 10) == u"c");
    XCTAssertTrue(resolved.text(7, 1).empty());
    XCTAssertTrue(resolved.text(1, 0).empty());
    XCTAssertTrue(resolved.text(UINT32_MAX, UINT32_MAX).empty());
    XCTAssertTrue(resolved.text(5, UINT32_MAX) == text(u"\xDE00" u"c"));
}

- (void)testEmptyDocumentHasNoText {
    atr::DocumentBuilder builder;
    atr::ResolvedDocument resolved = resolve(builder);

    XCTAssertTrue(resolved.paragraphs.empty());
    XCTAssertEqual(resolved.length(), 0u);
    XCTAssertTrue(resolved.text(0, 10).empty());
}

@end
