// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#import <XCTest/XCTest.h>

#include "atr/layout/Layout.hpp"

#include <set>
#include <string>

@interface FallbackFontTests : XCTestCase
@end

@implementation FallbackFontTests

// Every paragraph has its own typesetter, so without the shared cache
// CoreText would create a new fallback font object per paragraph.
- (void)testParagraphsShareFallbackFonts {
    const std::u16string text = u"abc สวัสดี مرحبا \U0001F600";
    atr::DocumentBuilder builder;

    for (int index = 0; index < 20; ++index) {
        builder.beginParagraph({}, {});
        builder.appendText(text.data(), text.size());
        builder.endParagraph();
    }

    std::shared_ptr<const atr::Document> document;
    XCTAssertEqual(builder.finish(document), atr::BuildStatus::Ok);
    atr::ResolvedDocument resolved = atr::resolve(*document);
    atr::FontTable fonts;
    fonts.defaultFont = atr::CFRef<CTFontRef>::adopt(CTFontCreateUIFontForLanguage(kCTFontUIFontSystem, 16, nullptr));
    auto layout = atr::computeLayout(*document, resolved, fonts, atr::Container{});

    std::set<const void *> objects;
    std::set<std::string> names;

    for (const atr::Line &line : layout->lines) {
        for (const atr::LineRun &run : line.runs) {
            auto font = static_cast<CTFontRef>(
                CFDictionaryGetValue(CTRunGetAttributes(run.run.get()), kCTFontAttributeName)
            );
            objects.insert(font);
            auto name = atr::CFRef<CFStringRef>::adopt(CTFontCopyPostScriptName(font));
            names.insert(std::string(CFStringGetCStringPtr(name.get(), kCFStringEncodingUTF8) ?: "?"));
        }
    }

    XCTAssertEqual(layout->lines.size(), 20u);
    XCTAssertGreaterThanOrEqual(names.size(), 3u);
    XCTAssertEqual(objects.size(), names.size());
}

@end
