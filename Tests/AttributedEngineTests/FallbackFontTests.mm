// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#import <XCTest/XCTest.h>

#include "atr/layout/Layout.hpp"

#include <set>
#include <string>
#include <thread>
#include <vector>

namespace {

atr::CFRef<CTFontRef> systemFont(double size) {
    return atr::CFRef<CTFontRef>::adopt(CTFontCreateUIFontForLanguage(kCTFontUIFontSystem, size, nullptr));
}

atr::CFRef<CFStringRef> makeString(const char16_t *text) {
    std::u16string value(text);
    return atr::CFRef<CFStringRef>::adopt(CFStringCreateWithCharacters(
        nullptr,
        reinterpret_cast<const UniChar *>(value.data()),
        static_cast<CFIndex>(value.size())
    ));
}

std::shared_ptr<const atr::Layout> layoutParagraph(const std::u16string &text, atr::FontTable &fonts, double width) {
    atr::DocumentBuilder builder;
    builder.beginParagraph({}, {});
    builder.appendText(text.data(), text.size());
    builder.endParagraph();
    std::shared_ptr<const atr::Document> document;
    builder.finish(document);
    atr::ResolvedDocument resolved = atr::resolve(*document);
    atr::Container container;
    container.width = width;
    return atr::computeLayout(*document, resolved, fonts, container);
}

CTFontRef runFont(const atr::LineRun &run) {
    return static_cast<CTFontRef>(CFDictionaryGetValue(CTRunGetAttributes(run.run.get()), kCTFontAttributeName));
}

} // namespace

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

- (void)testTheCacheKeysByDeclaredFontAndFallbackName {
    atr::FallbackFontCache cache;
    auto base = systemFont(16);
    auto thai = makeString(u"สวัสดี");
    auto arabic = makeString(u"مرحبا");

    CTFontRef first = cache.fallback(0, base.get(), thai.get(), CFRangeMake(0, 1));
    CTFontRef again = cache.fallback(0, base.get(), thai.get(), CFRangeMake(2, 1));
    CTFontRef otherScript = cache.fallback(0, base.get(), arabic.get(), CFRangeMake(0, 1));
    CTFontRef otherDeclared = cache.fallback(1, base.get(), thai.get(), CFRangeMake(0, 1));

    XCTAssertEqual(first, again);
    XCTAssertNotEqual(first, otherScript);
    // Another declared font may have another size, so it never shares.
    XCTAssertNotEqual(first, otherDeclared);
    XCTAssertEqualWithAccuracy(CTFontGetSize(first), 16, 0.001);
}

- (void)testTheCacheIsThreadSafe {
    atr::FallbackFontCache cache;
    auto base = systemFont(16);
    auto thai = makeString(u"สวัสดี");
    std::vector<CTFontRef> results(16);
    std::vector<std::thread> threads;

    for (size_t index = 0; index < results.size(); ++index) {
        threads.emplace_back([&, index] {
            results[index] = cache.fallback(0, base.get(), thai.get(), CFRangeMake(0, 1));
        });
    }

    for (std::thread &thread : threads) {
        thread.join();
    }

    for (CTFontRef font : results) {
        XCTAssertEqual(font, results.front());
    }
}

- (void)testDocumentsDoNotShareCaches {
    atr::FontTable first;
    first.defaultFont = systemFont(16);
    atr::FontTable second;
    second.defaultFont = first.defaultFont;
    auto a = layoutParagraph(u"สวัสดี", first, 300);
    auto b = layoutParagraph(u"สวัสดี", second, 300);

    XCTAssertNotEqual(runFont(a->lines[0].runs[0]), runFont(b->lines[0].runs[0]));
    XCTAssertTrue(first.fallbacks != second.fallbacks);
}

- (void)testBaseFontTextUsesNoFallback {
    atr::FontTable fonts;
    fonts.defaultFont = systemFont(16);
    auto layout = layoutParagraph(u"Plain ASCII text, 123!", fonts, 1000);

    for (const atr::LineRun &run : layout->lines[0].runs) {
        XCTAssertTrue(CFEqual(runFont(run), fonts.defaultFont.get()));
    }
}

- (void)testAssignedFallbacksKeepCoreTextWidths {
    const std::u16string text = u"abc สวัสดี مرحبا 中文 한국어 \U0001F600\U0001F468‍\U0001F469‍\U0001F467 é";
    atr::FontTable fonts;
    fonts.defaultFont = systemFont(16);
    auto layout = layoutParagraph(text, fonts, INFINITY);

    NSString *string = [NSString stringWithCharacters:reinterpret_cast<const unichar *>(text.data()) length:text.size()];
    NSDictionary *attributes = @{(id)kCTFontAttributeName: (__bridge id)fonts.defaultFont.get()};
    NSAttributedString *plain = [[NSAttributedString alloc] initWithString:string attributes:attributes];
    auto line = atr::CFRef<CTLineRef>::adopt(CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)plain));
    double expected = CTLineGetTypographicBounds(line.get(), nullptr, nullptr, nullptr)
        - CTLineGetTrailingWhitespaceWidth(line.get());

    XCTAssertEqual(layout->lines.size(), 1u);
    XCTAssertEqualWithAccuracy(layout->lines[0].width, expected, 0.5);
}

- (void)testFallbackRunsKeepTheDeclaredFontSize {
    atr::FontTable fonts;
    fonts.defaultFont = systemFont(16);
    fonts.fonts.push_back(systemFont(30));
    atr::DocumentBuilder builder;
    atr::TextStyle large;
    large.font = 0;
    const std::u16string text = u"ab中文";
    builder.beginParagraph({}, large);
    builder.appendText(text.data(), text.size());
    builder.endParagraph();
    std::shared_ptr<const atr::Document> document;
    builder.finish(document);
    atr::ResolvedDocument resolved = atr::resolve(*document);
    atr::Container container;
    auto layout = atr::computeLayout(*document, resolved, fonts, container);

    for (const atr::LineRun &run : layout->lines[0].runs) {
        XCTAssertEqualWithAccuracy(CTFontGetSize(runFont(run)), 30, 0.001);
    }
}

@end
