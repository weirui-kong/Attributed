// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#import "ATRDocument+Internal.h"

#import "ATRTextLayout+Internal.h"

#if !__has_feature(objc_arc)
#error "AttributedEngineObjC must be compiled with ARC."
#endif

namespace {

// UIFont and NSFont are toll-free bridged with CTFont.
atr::CFRef<CTFontRef> makeCTFont(ATRPlatformFont *font) {
    return atr::CFRef<CTFontRef>::retain((__bridge CTFontRef)font);
}

std::u16string makeUTF16(NSString *string) {
    std::u16string result(string.length, u'\0');
    [string getCharacters:reinterpret_cast<unichar *>(result.data())
                    range:NSMakeRange(0, string.length)];
    return result;
}

} // namespace

@implementation ATRDocument {
    std::shared_ptr<const atr::Document> _document;
    // Resolved once so every layout of this document shares it.
    atr::ResolvedDocument _resolved;
    atr::FontTable _fontTable;
    NSArray<ATRPlatformFont *> *_fonts;
    NSArray<ATRPlatformColor *> *_colors;
}

- (instancetype)initWithDocument:(std::shared_ptr<const atr::Document>)document
                           fonts:(NSArray<ATRPlatformFont *> *)fonts
                          colors:(NSArray<ATRPlatformColor *> *)colors
                     defaultFont:(ATRPlatformFont *)defaultFont {
    self = [super init];

    if (self) {
        _document = std::move(document);
        _resolved = atr::resolve(*_document);
        _fonts = [fonts copy];
        _colors = [colors copy];
        _fontTable.defaultFont = makeCTFont(defaultFont);

        for (ATRPlatformFont *font in _fonts) {
            _fontTable.fonts.push_back(makeCTFont(font));
        }
    }

    return self;
}

- (const atr::Document &)engineDocument {
    return *_document;
}

- (const atr::ResolvedDocument &)resolvedDocument {
    return _resolved;
}

- (const atr::FontTable &)fontTable {
    return _fontTable;
}

- (NSUInteger)fontCount {
    return _fonts.count;
}

- (NSUInteger)colorCount {
    return _colors.count;
}

- (NSUInteger)gradientCount {
    return _document->gradients().size();
}

- (NSUInteger)attachmentCount {
    return _document->attachments().size();
}

- (NSUInteger)interactionCount {
    return _document->interactions().size();
}

- (ATRGesture)gestureForInteraction:(uint32_t)interaction {
    const atr::Gesture &gesture = _document->interactions().at(interaction);
    return {
        static_cast<ATRGestureKind>(gesture.kind),
        gesture.tapCount,
        gesture.minimumPressDuration,
    };
}

- (NSRange)rangeForInteraction:(uint32_t)interaction {
    auto range = _resolved.interactionRanges.at(interaction);
    return NSMakeRange(range.first, range.second);
}

- (NSString *)textInRange:(NSRange)range {
    std::u16string text = _resolved.text(
        static_cast<uint32_t>(range.location),
        static_cast<uint32_t>(range.length)
    );
    return [NSString stringWithCharacters:reinterpret_cast<const unichar *>(text.data())
                                   length:text.size()];
}

- (ATRPlatformFont *)fontAtIndex:(NSUInteger)index {
    return _fonts[index];
}

- (ATRPlatformColor *)colorAtIndex:(NSUInteger)index {
    return _colors[index];
}

- (ATRTextLayout *)layoutWithContainer:(ATRTextContainer)container
                       truncationToken:(NSString *)truncationToken {
    atr::Container engineContainer;
    engineContainer.width = container.width;
    engineContainer.maxHeight = container.maxHeight;
    engineContainer.maxLines = container.maximumNumberOfLines;
    engineContainer.lineHeightMode = static_cast<atr::LineHeightMode>(container.lineHeightMode);

    if (truncationToken) {
        engineContainer.truncationToken = makeUTF16(truncationToken);
    }

    return [self layoutWithEngineContainer:engineContainer container:container];
}

- (ATRTextLayout *)layoutWithEngineContainer:(const atr::Container &)engineContainer
                                   container:(ATRTextContainer)container {
    auto layout = atr::computeLayout(*_document, _resolved, _fontTable, engineContainer);
    return [[ATRTextLayout alloc] initWithLayout:std::move(layout) document:self container:container];
}

- (NSString *)plainText {
    std::u16string text;

    for (size_t index = 0; index < _resolved.paragraphs.size(); ++index) {
        const atr::ResolvedParagraph &paragraph = _resolved.paragraphs[index];

        if (index > 0) {
            text.push_back(u'\n');
        }

        for (const atr::Run &run : paragraph.runs) {
            if (!run.attachment) {
                text.append(paragraph.text, run.location, run.length);
                continue;
            }

            const auto &label = _document->attachments()[*run.attachment].accessibilityLabel;

            if (label) {
                text.append(*label);
            }
        }
    }

    return [NSString stringWithCharacters:reinterpret_cast<const unichar *>(text.data())
                                   length:text.size()];
}

- (NSString *)resolvedDump {
    std::string output = _resolved.dump();
    return [[NSString alloc] initWithBytes:output.data()
                                    length:output.size()
                                  encoding:NSUTF8StringEncoding];
}

- (NSString *)dump {
    std::string output = _document->dump();
    output += "\n---";

    for (NSUInteger index = 0; index < _fonts.count; ++index) {
        ATRPlatformFont *font = _fonts[index];
        output += "\nf" + std::to_string(index) + " = " + font.fontName.UTF8String + " "
            + atr::formatNumber(font.pointSize);
    }

    for (NSUInteger index = 0; index < _colors.count; ++index) {
        output += "\nc" + std::to_string(index) + " = " + _colors[index].description.UTF8String;
    }

    return [[NSString alloc] initWithBytes:output.data()
                                    length:output.size()
                                  encoding:NSUTF8StringEncoding];
}

@end
