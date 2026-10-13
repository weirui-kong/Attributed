// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#import <XCTest/XCTest.h>

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

@end
