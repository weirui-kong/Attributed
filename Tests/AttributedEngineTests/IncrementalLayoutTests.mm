// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#import <XCTest/XCTest.h>

#include <algorithm>
#include <initializer_list>

#include "atr/layout/Layout.hpp"

@interface IncrementalLayoutTests : XCTestCase
@end

@implementation IncrementalLayoutTests {
    std::shared_ptr<const atr::Document> _document;
    atr::ResolvedDocument _resolved;
    atr::FontTable _fonts;
    uint32_t _image;
}

// Five spaced paragraphs; the third holds an unsized adaptive AsyncImage.
- (void)setUp {
    const std::u16string text = u"The quick brown fox jumps over the lazy dog and keeps running across the field.";
    atr::DocumentBuilder builder;
    atr::ParagraphStyle spaced;
    spaced.paragraphSpacing = 6;
    spaced.lineSpacing = 2;

    for (int index = 0; index < 5; ++index) {
        builder.beginParagraph(spaced, {});
        builder.appendText(text.data(), text.size());

        if (index == 2) {
            atr::AttachmentDescriptor image;
            image.sizeKind = atr::AttachmentSizeKind::Adaptive;
            image.maxWidth = 120;
            image.pipeline = atr::ImagePipeline::AsyncImage;
            XCTAssertEqual(builder.appendAttachment(image, _image), atr::BuildStatus::Ok);
            builder.appendText(text.data(), text.size());
        }

        builder.endParagraph();
    }

    XCTAssertEqual(builder.finish(_document), atr::BuildStatus::Ok);
    _resolved = atr::resolve(*_document);
    _fonts.defaultFont = atr::CFRef<CTFontRef>::adopt(CTFontCreateUIFontForLanguage(kCTFontUIFontSystem, 16, nullptr));
}

- (atr::Container)containerWithImageSize:(bool)loaded {
    atr::Container container;
    container.width = 240;

    if (loaded) {
        container.attachmentContentSizes[_image] = {200, 100};
    }

    return container;
}

- (void)testReusedLayoutMatchesAFullLayout {
    auto before = atr::computeLayout(*_document, _resolved, _fonts, [self containerWithImageSize:false]);
    atr::Container loaded = [self containerWithImageSize:true];
    auto incremental = atr::computeLayout(*_document, _resolved, _fonts, loaded, before.get());
    auto full = atr::computeLayout(*_document, _resolved, _fonts, loaded);

    XCTAssertEqual(incremental->lines.size(), full->lines.size());
    XCTAssertEqual(incremental->width, full->width);
    XCTAssertEqual(incremental->height, full->height);
    XCTAssertGreaterThan(full->height, before->height);

    for (size_t index = 0; index < full->lines.size(); ++index) {
        const atr::Line &a = incremental->lines[index];
        const atr::Line &b = full->lines[index];
        XCTAssertEqual(a.paragraph, b.paragraph);
        XCTAssertEqual(a.location, b.location);
        XCTAssertEqual(a.top, b.top);
        XCTAssertEqual(a.baseline, b.baseline);
        XCTAssertEqual(a.width, b.width);
        XCTAssertEqual(a.runs.size(), b.runs.size());
    }

    XCTAssertEqual(incremental->attachments.size(), 1u);
    XCTAssertEqual(incremental->attachments[0].frame.y, full->attachments[0].frame.y);
    XCTAssertEqual(incremental->attachments[0].frame.width, 120);
    XCTAssertEqual(incremental->hitRegions.size(), full->hitRegions.size());

    // Only the paragraph with the image was broken again; the others reuse
    // the previous CTLine objects.
    for (const atr::Line &line : incremental->lines) {
        bool reused = false;

        for (const atr::Line &old : before->lines) {
            reused = reused || old.line.get() == line.line.get();
        }

        XCTAssertEqual(reused, line.paragraph != 2);
    }
}

- (void)testLimitsDisableReuse {
    atr::Container limited = [self containerWithImageSize:false];
    limited.maxLines = 4;
    auto before = atr::computeLayout(*_document, _resolved, _fonts, limited);
    limited.attachmentContentSizes[_image] = {200, 100};
    auto after = atr::computeLayout(*_document, _resolved, _fonts, limited, before.get());

    XCTAssertEqual(after->lines.size(), 4u);
    XCTAssertNotEqual(after->lines[0].line.get(), before->lines[0].line.get());
}

- (void)assertLayout:(const atr::Layout &)actual equals:(const atr::Layout &)expected {
    XCTAssertEqual(actual.lines.size(), expected.lines.size());
    XCTAssertEqual(actual.width, expected.width);
    XCTAssertEqual(actual.height, expected.height);
    XCTAssertEqual(actual.truncated, expected.truncated);
    XCTAssertEqual(actual.attachments.size(), expected.attachments.size());
    XCTAssertEqual(actual.hitRegions.size(), expected.hitRegions.size());
    XCTAssertEqual(actual.decorations.size(), expected.decorations.size());

    for (size_t index = 0; index < std::min(actual.lines.size(), expected.lines.size()); ++index) {
        const atr::Line &a = actual.lines[index];
        const atr::Line &b = expected.lines[index];
        XCTAssertEqual(a.paragraph, b.paragraph);
        XCTAssertEqual(a.location, b.location);
        XCTAssertEqual(a.length, b.length);
        XCTAssertEqual(a.top, b.top);
        XCTAssertEqual(a.baseline, b.baseline);
        XCTAssertEqual(a.x, b.x);
        XCTAssertEqual(a.width, b.width);
    }
}

- (size_t)reusedLinesIn:(const atr::Layout &)layout from:(const atr::Layout &)previous {
    size_t count = 0;

    for (const atr::Line &line : layout.lines) {
        for (const atr::Line &old : previous.lines) {
            if (line.line && old.line.get() == line.line.get()) {
                ++count;
                break;
            }
        }
    }

    return count;
}

- (void)testUnchangedInputsReuseEveryLine {
    atr::Container container = [self containerWithImageSize:true];
    auto before = atr::computeLayout(*_document, _resolved, _fonts, container);
    auto again = atr::computeLayout(*_document, _resolved, _fonts, container, before.get());

    [self assertLayout:*again equals:*before];
    XCTAssertEqual([self reusedLinesIn:*again from:*before], before->lines.size());
}

- (void)testShrinkingBackMatchesAFullLayout {
    auto loaded = atr::computeLayout(*_document, _resolved, _fonts, [self containerWithImageSize:true]);
    atr::Container unloaded = [self containerWithImageSize:false];
    auto incremental = atr::computeLayout(*_document, _resolved, _fonts, unloaded, loaded.get());
    auto full = atr::computeLayout(*_document, _resolved, _fonts, unloaded);

    [self assertLayout:*incremental equals:*full];
    XCTAssertLessThan(full->height, loaded->height);
}

- (void)testOtherContainerChangesDisableReuse {
    atr::Container base = [self containerWithImageSize:false];
    auto before = atr::computeLayout(*_document, _resolved, _fonts, base);

    atr::Container wider = [self containerWithImageSize:true];
    wider.width = 300;
    atr::Container glyphBounds = [self containerWithImageSize:true];
    glyphBounds.lineHeightMode = atr::LineHeightMode::GlyphBounds;
    atr::Container token = [self containerWithImageSize:true];
    token.truncationToken = u"...";
    atr::Container tall = [self containerWithImageSize:true];
    tall.maxHeight = 10000;

    for (const atr::Container &container : {wider, glyphBounds, token, tall}) {
        auto after = atr::computeLayout(*_document, _resolved, _fonts, container, before.get());
        auto full = atr::computeLayout(*_document, _resolved, _fonts, container);
        [self assertLayout:*after equals:*full];
        XCTAssertEqual([self reusedLinesIn:*after from:*before], 0u);
    }
}

- (void)testATruncatedPreviousLayoutIsNotReused {
    atr::Container limited = [self containerWithImageSize:false];
    limited.maxHeight = 60;
    auto before = atr::computeLayout(*_document, _resolved, _fonts, limited);
    XCTAssertTrue(before->truncated);

    atr::Container free = [self containerWithImageSize:true];
    auto after = atr::computeLayout(*_document, _resolved, _fonts, free, before.get());
    auto full = atr::computeLayout(*_document, _resolved, _fonts, free);

    [self assertLayout:*after equals:*full];
    XCTAssertEqual([self reusedLinesIn:*after from:*before], 0u);
}

- (void)testOnlyParagraphsWithChangedImagesBreakAgain {
    const std::u16string text = u"Some words that wrap across a couple of lines in a narrow box.";
    atr::DocumentBuilder builder;
    uint32_t images[2] = {};

    for (int index = 0; index < 4; ++index) {
        builder.beginParagraph({}, {});
        builder.appendText(text.data(), text.size());

        if (index == 1 || index == 3) {
            atr::AttachmentDescriptor image;
            image.sizeKind = atr::AttachmentSizeKind::Adaptive;
            image.pipeline = atr::ImagePipeline::AsyncImage;
            builder.appendAttachment(image, images[index == 1 ? 0 : 1]);
        }

        builder.endParagraph();
    }

    std::shared_ptr<const atr::Document> document;
    builder.finish(document);
    atr::ResolvedDocument resolved = atr::resolve(*document);
    atr::Container container;
    container.width = 200;
    container.attachmentContentSizes[images[0]] = {50, 50};
    container.attachmentContentSizes[images[1]] = {50, 50};
    auto before = atr::computeLayout(*document, resolved, _fonts, container);

    container.attachmentContentSizes[images[1]] = {80, 80};
    auto after = atr::computeLayout(*document, resolved, _fonts, container, before.get());
    auto full = atr::computeLayout(*document, resolved, _fonts, container);

    [self assertLayout:*after equals:*full];

    for (const atr::Line &line : after->lines) {
        bool reused = false;

        for (const atr::Line &old : before->lines) {
            reused = reused || old.line.get() == line.line.get();
        }

        XCTAssertEqual(reused, line.paragraph != 3, @"paragraph %u", line.paragraph);
    }

    // Removing a size that was set counts as a change too.
    container.attachmentContentSizes.erase(images[0]);
    auto removed = atr::computeLayout(*document, resolved, _fonts, container, after.get());
    [self assertLayout:*removed equals:*atr::computeLayout(*document, resolved, _fonts, container)];
}

- (void)testAPreviousLayoutOfALongerDocumentIsIgnored {
    atr::DocumentBuilder builder;
    const std::u16string text = u"Short";
    builder.beginParagraph({}, {});
    builder.appendText(text.data(), text.size());
    builder.endParagraph();
    std::shared_ptr<const atr::Document> small;
    builder.finish(small);
    atr::ResolvedDocument smallResolved = atr::resolve(*small);

    // The previous layout has lines for paragraphs this document lacks.
    auto foreign = atr::computeLayout(*_document, _resolved, _fonts, [self containerWithImageSize:false]);
    atr::Container container;
    container.width = 240;
    auto after = atr::computeLayout(*small, smallResolved, _fonts, container, foreign.get());
    auto full = atr::computeLayout(*small, smallResolved, _fonts, container);

    [self assertLayout:*after equals:*full];
}

@end
