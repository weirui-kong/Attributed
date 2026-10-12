// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#import "ATRDocumentBuilder.h"

#import "ATRDocument+Internal.h"

#if !__has_feature(objc_arc)
#error "AttributedEngineObjC must be compiled with ARC."
#endif

const uint32_t ATRNoInteraction = atr::kNoInteraction;

namespace {

atr::Fill makeFill(const ATRFill &fill) {
    return {static_cast<atr::FillKind>(fill.kind), fill.index};
}

atr::TextStyle makeTextStyle(const ATRTextStyle &style) {
    atr::TextStyle result;

    if (style.fields & ATRTextStyleFieldFont) {
        result.font = style.font;
    }

    if (style.fields & ATRTextStyleFieldForeground) {
        result.foreground = makeFill(style.foreground);
    }

    if (style.fields & ATRTextStyleFieldBackgroundColor) {
        result.backgroundColor = style.backgroundColor;
    }

    if (style.fields & ATRTextStyleFieldKern) {
        result.kern = style.kern;
    }

    if (style.fields & ATRTextStyleFieldBaselineOffset) {
        result.baselineOffset = style.baselineOffset;
    }

    if (style.fields & ATRTextStyleFieldUnderline) {
        atr::Underline underline;
        underline.lines = static_cast<atr::UnderlineLines>(style.underline.lines);
        underline.pattern = static_cast<atr::UnderlinePattern>(style.underline.pattern);

        if (style.underline.thickness > 0) {
            underline.thickness = style.underline.thickness;
        }

        underline.corners = static_cast<atr::UnderlineCorners>(style.underline.corners);
        underline.cornerRadius = style.underline.cornerRadius;

        result.underline = underline;
    }

    if (style.fields & ATRTextStyleFieldUnderlineFill) {
        result.underlineFill = makeFill(style.underlineFill);
    }

    return result;
}

atr::ParagraphStyle makeParagraphStyle(const ATRParagraphStyle &style) {
    atr::ParagraphStyle result;

    if (style.fields & ATRParagraphStyleFieldAlignment) {
        result.alignment = static_cast<atr::TextAlignment>(style.alignment);
    }

    if (style.fields & ATRParagraphStyleFieldWritingDirection) {
        result.writingDirection = static_cast<atr::WritingDirection>(style.writingDirection);
    }

    if (style.fields & ATRParagraphStyleFieldLineSpacing) {
        result.lineSpacing = style.lineSpacing;
    }

    if (style.fields & ATRParagraphStyleFieldParagraphSpacing) {
        result.paragraphSpacing = style.paragraphSpacing;
    }

    return result;
}

std::u16string makeUTF16(NSString *string) {
    std::u16string result(string.length, u'\0');
    [string getCharacters:reinterpret_cast<unichar *>(result.data())
                    range:NSMakeRange(0, string.length)];
    return result;
}

void check(atr::BuildStatus status) {
    if (status != atr::BuildStatus::Ok) {
        [NSException raise:NSInternalInconsistencyException
                    format:@"%s", atr::describe(status)];
    }
}

} // namespace

@implementation ATRDocumentBuilder {
    atr::DocumentBuilder _builder;
    NSMutableArray<ATRPlatformFont *> *_fonts;
    NSMutableArray<ATRPlatformColor *> *_colors;
    NSMapTable<ATRPlatformFont *, NSNumber *> *_fontIndices;
    NSMapTable<ATRPlatformColor *, NSNumber *> *_colorIndices;
}

- (instancetype)init {
    self = [super init];

    if (self) {
        _fonts = [NSMutableArray array];
        _colors = [NSMutableArray array];
        _fontIndices = [NSMapTable strongToStrongObjectsMapTable];
        _colorIndices = [NSMapTable strongToStrongObjectsMapTable];

#if TARGET_OS_OSX
        int32_t label = [self registerColor:NSColor.labelColor];
#else
        int32_t label = [self registerColor:UIColor.labelColor];
#endif
        atr::TextStyle base;
        base.foreground = atr::Fill{atr::FillKind::Color, label};
        _builder.setBaseTextStyle(base);
    }

    return self;
}

- (int32_t)registerFont:(ATRPlatformFont *)font {
    return [self registerObject:font in:_fonts indices:_fontIndices];
}

- (int32_t)registerColor:(ATRPlatformColor *)color {
    return [self registerObject:color in:_colors indices:_colorIndices];
}

- (int32_t)registerObject:(id)object in:(NSMutableArray *)objects indices:(NSMapTable *)indices {
    if (NSNumber *index = [indices objectForKey:object]) {
        return index.intValue;
    }

    int32_t index = static_cast<int32_t>(objects.count);
    [objects addObject:object];
    [indices setObject:@(index) forKey:object];
    return index;
}

- (int32_t)registerGradientWithColors:(const int32_t *)colors
                            locations:(const double *)locations
                                count:(NSUInteger)count
                           descriptor:(ATRGradientDescriptor)descriptor {
    if (count == 0) {
        [NSException raise:NSInvalidArgumentException format:@"A gradient needs at least one color."];
    }

    atr::Gradient gradient;
    gradient.colors.assign(colors, colors + count);

    if (locations) {
        gradient.locations = std::vector<double>(locations, locations + count);
    }

    gradient.startX = descriptor.startX;
    gradient.startY = descriptor.startY;
    gradient.endX = descriptor.endX;
    gradient.endY = descriptor.endY;
    gradient.scope = static_cast<atr::GradientScope>(descriptor.scope);

    int32_t index = _builder.registerGradient(gradient);

    if (index < 0) {
        check(atr::BuildStatus::AlreadyFinished);
    }

    return index;
}

- (uint32_t)registerInteractionWithGesture:(ATRGesture)gesture {
    atr::Gesture value;
    value.kind = static_cast<atr::GestureKind>(gesture.kind);
    value.tapCount = gesture.tapCount;
    value.minimumPressDuration = gesture.minimumPressDuration;
    uint32_t interaction = _builder.registerInteraction(value);

    if (interaction == atr::kNoInteraction) {
        check(atr::BuildStatus::AlreadyFinished);
    }

    return interaction;
}

- (void)beginParagraph:(ATRParagraphStyle)paragraphStyle textStyle:(ATRTextStyle)textStyle {
    check(_builder.beginParagraph(makeParagraphStyle(paragraphStyle), makeTextStyle(textStyle)));
}

- (void)endParagraph {
    check(_builder.endParagraph());
}

- (void)pushSpan:(ATRTextStyle)textStyle interaction:(uint32_t)interaction {
    check(_builder.pushSpan(makeTextStyle(textStyle), interaction));
}

- (void)popSpan {
    check(_builder.popSpan());
}

- (void)appendText:(NSString *)text {
    std::u16string characters = makeUTF16(text);
    check(_builder.appendText(characters.data(), characters.size()));
}

- (uint32_t)appendAttachment:(ATRAttachmentDescriptor)descriptor
          accessibilityLabel:(NSString *)accessibilityLabel {
    atr::AttachmentDescriptor result;
    result.sizeKind = static_cast<atr::AttachmentSizeKind>(descriptor.sizeKind);
    result.width = descriptor.width;
    result.height = descriptor.height;

    if (descriptor.fields & ATRAttachmentFieldMaxWidth) {
        result.maxWidth = descriptor.maxWidth;
    }

    if (descriptor.fields & ATRAttachmentFieldMaxHeight) {
        result.maxHeight = descriptor.maxHeight;
    }

    result.alignmentKind = static_cast<atr::AttachmentAlignmentKind>(descriptor.alignmentKind);
    result.alignmentOffset = descriptor.alignmentOffset;
    result.pipeline = static_cast<atr::ImagePipeline>(descriptor.pipeline);

    if (descriptor.fields & ATRAttachmentFieldContentSize) {
        result.contentWidth = descriptor.contentWidth;
        result.contentHeight = descriptor.contentHeight;
    }

    if (accessibilityLabel.length > 0) {
        result.accessibilityLabel = makeUTF16(accessibilityLabel);
    }

    uint32_t identifier = 0;
    check(_builder.appendAttachment(result, identifier));
    return identifier;
}

- (ATRDocument *)finish {
    std::shared_ptr<const atr::Document> document;
    check(_builder.finish(document));
#if TARGET_OS_OSX
    ATRPlatformFont *defaultFont = [NSFont systemFontOfSize:NSFont.systemFontSize];
#else
    ATRPlatformFont *defaultFont = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
#endif
    return [[ATRDocument alloc] initWithDocument:std::move(document)
                                           fonts:_fonts
                                          colors:_colors
                                     defaultFont:defaultFont];
}

@end
