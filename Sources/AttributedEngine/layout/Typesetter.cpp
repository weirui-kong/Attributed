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
    : context_(context), paragraphs_(context.resolved.paragraphs.size()) {
    for (const ResolvedParagraph &paragraph : context.resolved.paragraphs) {
        for (size_t index = 0; index < paragraph.runs.size(); ++index) {
            if (const auto &attachment = paragraph.runs[index].attachment) {
                attachmentRuns_[*attachment] = {paragraph.runs[index].style, neighborTextStyle(paragraph, index)};
            }
        }
    }
}

const AttachmentMetrics &Typesetter::attachmentMetrics(uint32_t attachment) const {
    if (auto found = attachmentMetrics_.find(attachment); found != attachmentMetrics_.end()) {
        return found->second;
    }

    const AttachmentRun &run = attachmentRuns_.at(attachment);
    return attachmentMetrics_[attachment] = measure(attachment, run.style, run.neighborStyle);
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
            addAttachment(runAttributes.get(), *run.attachment);
        }

        CFAttributedStringSetAttributes(string, CFRangeMake(run.location, run.length), runAttributes.get(), true);

        if (!run.attachment) {
            assignFallbackFonts(string, characters.get(), paragraph.text, run);
        }
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

// Gives characters the run's font cannot draw the shared fallback font
// CoreText would pick, a whole composed character sequence at a time.
void Typesetter::assignFallbackFonts(
    CFMutableAttributedStringRef string,
    CFStringRef characters,
    const std::u16string &text,
    const Run &run
) {
    int32_t fontIndex = context_.resolved.styles[run.style].font;
    CTFontRef base = context_.fonts.font(fontIndex);
    const auto *units = reinterpret_cast<const UniChar *>(text.data()) + run.location;
    std::vector<CGGlyph> glyphs(run.length);

    if (CTFontGetGlyphsForCharacters(base, units, glyphs.data(), static_cast<CFIndex>(run.length))) {
        return;
    }

    const CFIndex runEnd = run.location + run.length;
    auto covered = [&](CTFontRef font, CFRange sequence) {
        CGGlyph sequenceGlyphs[16];
        std::vector<CGGlyph> heap;
        CGGlyph *buffer = sequence.length <= 16 ? sequenceGlyphs : (heap.resize(sequence.length), heap.data());
        return CTFontGetGlyphsForCharacters(
            font,
            units + (sequence.location - run.location),
            buffer,
            sequence.length
        );
    };
    auto sequenceAt = [&](CFIndex index) {
        CFRange sequence = CFStringGetRangeOfComposedCharactersAtIndex(characters, index);
        // Keep sequences inside the run; styles may split a sequence.
        CFIndex start = std::max<CFIndex>(sequence.location, run.location);
        CFIndex end = std::min<CFIndex>(sequence.location + sequence.length, runEnd);
        return CFRangeMake(start, end - start);
    };

    CFIndex index = run.location;

    while (index < runEnd) {
        if (glyphs[index - run.location] != 0) {
            index += 1;
            continue;
        }

        // The uncovered stretch, widened to whole sequences.
        CFRange first = sequenceAt(index);
        CFIndex start = first.location;
        CFIndex end = first.location + first.length;

        while (end < runEnd && glyphs[end - run.location] == 0) {
            CFRange next = sequenceAt(end);
            end = next.location + next.length;
        }

        // Split the stretch where one fallback stops covering it.
        while (start < end) {
            CTFontRef fallback = context_.fonts.fallbacks->fallback(
                fontIndex,
                base,
                characters,
                CFRangeMake(start, end - start)
            );
            CFIndex stop = start;

            do {
                CFRange sequence = sequenceAt(stop);

                if (stop > start && !covered(fallback, sequence)) {
                    break;
                }

                stop = sequence.location + sequence.length;
            } while (stop < end);

            CFAttributedStringSetAttribute(string, CFRangeMake(start, stop - start), kCTFontAttributeName, fallback);
            start = stop;
        }

        index = end;
    }
}

AttachmentMetrics Typesetter::measure(
    uint32_t attachment,
    uint32_t styleIndex,
    std::optional<uint32_t> neighborStyle
) const {
    const ResolvedTextStyle &style = context_.resolved.styles[styleIndex];
    const AttachmentDescriptor &descriptor = context_.document.attachments()[attachment];
    std::optional<std::pair<double, double>> contentSize;

    if (auto found = context_.container.attachmentContentSizes.find(attachment);
        found != context_.container.attachmentContentSizes.end()) {
        contentSize = found->second;
    }

    AttachmentMetrics metrics;
    bool unsized = descriptor.kind == AttachmentKind::Image && descriptor.pipeline == ImagePipeline::AsyncImage
        && descriptor.sizeKind == AttachmentSizeKind::Adaptive && !contentSize
        && !(descriptor.contentWidth && descriptor.contentHeight);

    // As tall as the adjacent character and on its baseline, so the line
    // keeps the height it would have without the attachment.
    auto adjacentHeight = [&](CTFontRef fallback) {
        const ResolvedTextStyle *neighbor = neighborStyle ? &context_.resolved.styles[*neighborStyle] : nullptr;
        CTFontRef font = neighbor ? context_.fonts.font(neighbor->font) : fallback;
        double descent = CTFontGetDescent(font);
        metrics.height = CTFontGetAscent(font) + descent;
        metrics.originY = (neighbor ? neighbor->baselineOffset : 0) - descent;
    };

    if (descriptor.kind == AttachmentKind::Spacer) {
        // Without adjacent text, a spacer takes its own font's height.
        metrics.width = descriptor.width;

        if (descriptor.inferredHeight) {
            adjacentHeight(context_.fonts.font(style.font));
        } else {
            // On the baseline, like a fixed image; the run's own baseline
            // offset is applied by line metrics.
            metrics.height = descriptor.height;
            metrics.originY = 0;
        }
    } else if (unsized) {
        // An AsyncImage with no size yet is a zero-width placeholder until
        // the image arrives. Without adjacent text, the default font sizes
        // it.
        metrics.width = 0;
        adjacentHeight(context_.fonts.defaultFont.get());
    } else {
        metrics = measureAttachment(descriptor, contentSize, context_.fonts.font(style.font), context_.container.width);
    }

    return metrics;
}

void Typesetter::addAttachment(CFMutableDictionaryRef attributes, uint32_t attachment) {
    const AttachmentMetrics &metrics = attachmentMetrics(attachment);

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
