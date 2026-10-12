// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#include "Typesetter.hpp"

namespace atr::layout {

namespace {

struct DelegateMetrics {
    double ascent;
    double descent;
    double width;
};

CGFloat delegateAscent(void *ref) {
    return static_cast<DelegateMetrics *>(ref)->ascent;
}

CGFloat delegateDescent(void *ref) {
    return static_cast<DelegateMetrics *>(ref)->descent;
}

CGFloat delegateWidth(void *ref) {
    return static_cast<DelegateMetrics *>(ref)->width;
}

void delegateDealloc(void *ref) {
    delete static_cast<DelegateMetrics *>(ref);
}

AttachmentMetrics measureAttachment(
    const AttachmentDescriptor &descriptor,
    std::optional<std::pair<double, double>> contentSize,
    CTFontRef font,
    double availableWidth
) {
    AttachmentMetrics metrics;

    if (!contentSize && descriptor.contentWidth && descriptor.contentHeight) {
        contentSize = std::make_pair(*descriptor.contentWidth, *descriptor.contentHeight);
    }

    if (descriptor.sizeKind == AttachmentSizeKind::Fixed) {
        metrics.width = descriptor.width;
        metrics.height = descriptor.height;
    } else if (contentSize && contentSize->first > 0 && contentSize->second > 0) {
        // Adaptive: keep the aspect ratio, fit the maxima and the line, and
        // never upscale.
        double contentWidth = contentSize->first;
        double contentHeight = contentSize->second;
        std::optional<double> widthLimit = descriptor.maxWidth;

        if (std::isfinite(availableWidth)) {
            widthLimit = std::min(widthLimit.value_or(availableWidth), availableWidth);
        }

        double scale = 1;

        if (widthLimit) {
            scale = std::min(scale, *widthLimit / contentWidth);
        }

        if (descriptor.maxHeight) {
            scale = std::min(scale, *descriptor.maxHeight / contentHeight);
        }

        metrics.width = contentWidth * scale;
        metrics.height = contentHeight * scale;
    }

    double capHeight = CTFontGetCapHeight(font);
    double descender = -CTFontGetDescent(font);

    switch (descriptor.alignmentKind) {
    case AttachmentAlignmentKind::Baseline:
        metrics.originY = 0;
        break;
    case AttachmentAlignmentKind::Center:
        metrics.originY = (capHeight + descender - metrics.height) / 2;
        break;
    case AttachmentAlignmentKind::Top:
        metrics.originY = capHeight - metrics.height;
        break;
    case AttachmentAlignmentKind::Bottom:
        metrics.originY = descender;
        break;
    case AttachmentAlignmentKind::Offset:
        metrics.originY = descriptor.alignmentOffset;
        break;
    }

    return metrics;
}

// The style of the text right before the run, else right after it.
std::optional<uint32_t> neighborTextStyle(const ResolvedParagraph &paragraph, size_t index) {
    if (index > 0 && !paragraph.runs[index - 1].attachment) {
        return paragraph.runs[index - 1].style;
    }

    if (index + 1 < paragraph.runs.size() && !paragraph.runs[index + 1].attachment) {
        return paragraph.runs[index + 1].style;
    }

    return std::nullopt;
}

} // namespace

Typesetter::Typesetter(const LayoutContext &context)
    : context_(context), paragraphs_(context.resolved.paragraphs.size()) {}

const AttachmentMetrics &Typesetter::attachmentMetrics(uint32_t attachment) const {
    return attachmentMetrics_.at(attachment);
}

CFRef<CFMutableDictionaryRef> Typesetter::attributes(uint32_t styleIndex) const {
    const ResolvedTextStyle &style = context_.resolved.styles[styleIndex];
    auto attributes = CFRef<CFMutableDictionaryRef>::adopt(CFDictionaryCreateMutable(
        nullptr,
        0,
        &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks
    ));
    CFDictionarySetValue(attributes.get(), kCTFontAttributeName, context_.fonts.font(style.font));
    CFDictionarySetValue(
        attributes.get(),
        kStyleAttribute,
        makeNumber(static_cast<int32_t>(styleIndex)).get()
    );

    if (style.kern != 0) {
        CFDictionarySetValue(attributes.get(), kCTKernAttributeName, makeNumber(style.kern).get());
    }

    // Layout is color-independent; the renderer sets each run's fill.
    CFDictionarySetValue(attributes.get(), kCTForegroundColorFromContextAttributeName, kCFBooleanTrue);
    return attributes;
}

ParagraphText &Typesetter::paragraph(uint32_t index) {
    ParagraphText &text = paragraphs_[index];

    if (text.string) {
        return text;
    }

    const ResolvedParagraph &paragraph = context_.resolved.paragraphs[index];
    auto characters = CFRef<CFStringRef>::adopt(CFStringCreateWithCharacters(
        nullptr,
        reinterpret_cast<const UniChar *>(paragraph.text.data()),
        static_cast<CFIndex>(paragraph.text.size())
    ));
    text.string = CFRef<CFMutableAttributedStringRef>::adopt(CFAttributedStringCreateMutable(nullptr, 0));
    CFMutableAttributedStringRef string = text.string.get();
    CFAttributedStringReplaceString(string, CFRangeMake(0, 0), characters.get());
    CFAttributedStringBeginEditing(string);

    for (size_t runIndex = 0; runIndex < paragraph.runs.size(); ++runIndex) {
        const Run &run = paragraph.runs[runIndex];
        auto runAttributes = attributes(run.style);

        if (run.attachment) {
            addAttachment(runAttributes.get(), *run.attachment, run.style, neighborTextStyle(paragraph, runIndex));
        }

        CFAttributedStringSetAttributes(string, CFRangeMake(run.location, run.length), runAttributes.get(), true);
    }

    CTWritingDirection direction = paragraph.style.direction == WritingDirection::RightToLeft
        ? kCTWritingDirectionRightToLeft
        : kCTWritingDirectionLeftToRight;
    CTParagraphStyleSetting setting = {
        kCTParagraphStyleSpecifierBaseWritingDirection,
        sizeof(direction),
        &direction,
    };
    auto paragraphStyle = CFRef<CTParagraphStyleRef>::adopt(CTParagraphStyleCreate(&setting, 1));
    CFAttributedStringSetAttribute(
        string,
        CFRangeMake(0, CFAttributedStringGetLength(string)),
        kCTParagraphStyleAttributeName,
        paragraphStyle.get()
    );
    CFAttributedStringEndEditing(string);

    text.typesetter = CFRef<CTTypesetterRef>::adopt(CTTypesetterCreateWithAttributedString(string));
    return text;
}

void Typesetter::addAttachment(
    CFMutableDictionaryRef attributes,
    uint32_t attachment,
    uint32_t styleIndex,
    std::optional<uint32_t> neighborStyle
) {
    const ResolvedTextStyle &style = context_.resolved.styles[styleIndex];
    const AttachmentDescriptor &descriptor = context_.document.attachments()[attachment];
    std::optional<std::pair<double, double>> contentSize;

    if (auto found = context_.container.attachmentContentSizes.find(attachment);
        found != context_.container.attachmentContentSizes.end()) {
        contentSize = found->second;
    }

    AttachmentMetrics metrics;
    bool unsized = descriptor.pipeline == ImagePipeline::AsyncImage
        && descriptor.sizeKind == AttachmentSizeKind::Adaptive && !contentSize
        && !(descriptor.contentWidth && descriptor.contentHeight);

    if (unsized) {
        // An AsyncImage with no size yet is a zero-width placeholder as tall
        // as the adjacent character, so the line keeps its height until the
        // image arrives. Without adjacent text, the default font sizes it.
        const ResolvedTextStyle *neighbor = neighborStyle ? &context_.resolved.styles[*neighborStyle] : nullptr;
        CTFontRef font = neighbor ? context_.fonts.font(neighbor->font) : context_.fonts.defaultFont.get();
        double descent = CTFontGetDescent(font);
        metrics.width = 0;
        metrics.height = CTFontGetAscent(font) + descent;
        metrics.originY = (neighbor ? neighbor->baselineOffset : 0) - descent;
    } else {
        metrics = measureAttachment(descriptor, contentSize, context_.fonts.font(style.font), context_.container.width);
    }

    attachmentMetrics_[attachment] = metrics;

    CTRunDelegateCallbacks callbacks = {};
    callbacks.version = kCTRunDelegateVersion1;
    callbacks.getAscent = delegateAscent;
    callbacks.getDescent = delegateDescent;
    callbacks.getWidth = delegateWidth;
    callbacks.dealloc = delegateDealloc;
    auto *delegateMetrics = new DelegateMetrics{
        std::max(0.0, metrics.originY + metrics.height),
        std::max(0.0, -metrics.originY),
        metrics.width,
    };
    auto delegate = CFRef<CTRunDelegateRef>::adopt(CTRunDelegateCreate(&callbacks, delegateMetrics));

    if (delegate) {
        CFDictionarySetValue(attributes, kCTRunDelegateAttributeName, delegate.get());
    } else {
        // The delegate owns the payload only once it exists.
        delete delegateMetrics;
    }

    CFDictionarySetValue(attributes, kAttachmentAttribute, makeNumber(static_cast<int32_t>(attachment)).get());
}

} // namespace atr::layout
