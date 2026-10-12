// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#include "atr/Layout.hpp"

#include <algorithm>
#include <map>
#include <unordered_map>

namespace atr {

namespace {

// Private attributes carried through CoreText so every CTRun, including
// truncation token runs, maps back to its resolved style and attachment.
const CFStringRef kStyleAttribute = CFSTR("ATRStyle");
const CFStringRef kAttachmentAttribute = CFSTR("ATRAttachment");

// Wrapping is disabled by laying out against a width no line reaches.
constexpr double kUnboundedWidth = 1e9;
constexpr double kMergeTolerance = 0.5;

struct AttachmentMetrics {
    double width = 0;
    double height = 0;
    // Bottom edge relative to the baseline, positive upward.
    double originY = 0;
};

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

CFRef<CFNumberRef> makeNumber(int32_t value) {
    return CFRef<CFNumberRef>::adopt(CFNumberCreate(nullptr, kCFNumberSInt32Type, &value));
}

CFRef<CFNumberRef> makeNumber(double value) {
    return CFRef<CFNumberRef>::adopt(CFNumberCreate(nullptr, kCFNumberDoubleType, &value));
}

std::optional<int32_t> intAttribute(CFDictionaryRef attributes, CFStringRef key) {
    auto number = static_cast<CFNumberRef>(CFDictionaryGetValue(attributes, key));

    if (!number) {
        return std::nullopt;
    }

    int32_t value = 0;
    CFNumberGetValue(number, kCFNumberSInt32Type, &value);
    return value;
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

struct LineMetrics {
    double ascent = 0;
    double descent = 0;
    double leading = 0;
    double inkAscent = 0;
    double inkDescent = 0;
};

// Union of the run's glyph bounding boxes relative to the baseline, positive
// upward. Glyph positions carry the vertical offsets of stacked marks.
void addInkBounds(CTRunRef run, CTFontRef font, double offset, LineMetrics &metrics) {
    CFIndex count = CTRunGetGlyphCount(run);

    if (!font || count == 0) {
        return;
    }

    std::vector<CGGlyph> glyphs(count);
    std::vector<CGPoint> positions(count);
    std::vector<CGRect> rects(count);
    CTRunGetGlyphs(run, CFRangeMake(0, 0), glyphs.data());
    CTRunGetPositions(run, CFRangeMake(0, 0), positions.data());
    CTFontGetBoundingRectsForGlyphs(
        font,
        kCTFontOrientationHorizontal,
        glyphs.data(),
        rects.data(),
        count
    );

    for (CFIndex index = 0; index < count; ++index) {
        if (CGRectIsEmpty(rects[index])) {
            continue;
        }

        double top = positions[index].y + CGRectGetMaxY(rects[index]) + offset;
        double bottom = positions[index].y + CGRectGetMinY(rects[index]) + offset;
        metrics.inkAscent = std::max(metrics.inkAscent, top);
        metrics.inkDescent = std::max(metrics.inkDescent, -bottom);
    }
}

class LayoutBuilder {
public:
    LayoutBuilder(
        const Document &document,
        const ResolvedDocument &resolved,
        const FontTable &fonts,
        const Container &container
    )
        : document_(document),
          resolved_(resolved),
          fonts_(fonts),
          container_(container),
          finiteWidth_(std::isfinite(container.width)),
          breakWidth_(finiteWidth_ ? container.width : kUnboundedWidth),
          texts_(resolved.paragraphs.size()),
          layout_(std::make_shared<Layout>()) {}

    std::shared_ptr<const Layout> run() {
        if (!(container_.width > 0)) {
            return layout_;
        }

        breakLines();
        collectRuns();
        measure();
        return layout_;
    }

private:
    struct ParagraphText {
        CFRef<CFMutableAttributedStringRef> string;
        CFRef<CTTypesetterRef> typesetter;
    };

    const Document &document_;
    const ResolvedDocument &resolved_;
    const FontTable &fonts_;
    const Container &container_;
    const bool finiteWidth_;
    const double breakWidth_;
    std::vector<ParagraphText> texts_;
    std::unordered_map<uint32_t, AttachmentMetrics> attachmentMetrics_;
    std::map<std::pair<int32_t, uint32_t>, uint32_t> groupIndices_;
    std::shared_ptr<Layout> layout_;
    double cursor_ = 0;

    CFRef<CFMutableDictionaryRef> makeAttributes(uint32_t styleIndex) {
        const ResolvedTextStyle &style = resolved_.styles[styleIndex];
        auto attributes = CFRef<CFMutableDictionaryRef>::adopt(CFDictionaryCreateMutable(
            nullptr,
            0,
            &kCFTypeDictionaryKeyCallBacks,
            &kCFTypeDictionaryValueCallBacks
        ));
        CFDictionarySetValue(attributes.get(), kCTFontAttributeName, fonts_.font(style.font));
        CFDictionarySetValue(
            attributes.get(),
            kStyleAttribute,
            makeNumber(static_cast<int32_t>(styleIndex)).get()
        );

        if (style.kern != 0) {
            CFDictionarySetValue(attributes.get(), kCTKernAttributeName, makeNumber(style.kern).get());
        }

        // Layout is color-independent; the renderer sets each run's fill.
        CFDictionarySetValue(
            attributes.get(),
            kCTForegroundColorFromContextAttributeName,
            kCFBooleanTrue
        );

        return attributes;
    }

    ParagraphText &paragraphText(uint32_t index) {
        ParagraphText &text = texts_[index];

        if (text.string) {
            return text;
        }

        const ResolvedParagraph &paragraph = resolved_.paragraphs[index];
        auto characters = CFRef<CFStringRef>::adopt(CFStringCreateWithCharacters(
            nullptr,
            reinterpret_cast<const UniChar *>(paragraph.text.data()),
            static_cast<CFIndex>(paragraph.text.size())
        ));
        text.string = CFRef<CFMutableAttributedStringRef>::adopt(
            CFAttributedStringCreateMutable(nullptr, 0)
        );
        CFMutableAttributedStringRef string = text.string.get();
        CFAttributedStringReplaceString(string, CFRangeMake(0, 0), characters.get());
        CFAttributedStringBeginEditing(string);

        for (size_t index = 0; index < paragraph.runs.size(); ++index) {
            const Run &run = paragraph.runs[index];
            CFRange range = CFRangeMake(run.location, run.length);
            auto attributes = makeAttributes(run.style);

            if (run.attachment) {
                addAttachment(attributes.get(), *run.attachment, run.style, neighborTextStyle(paragraph, index));
            }

            CFAttributedStringSetAttributes(string, range, attributes.get(), true);
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

    // The style of the text right before the run, else right after it.
    static std::optional<uint32_t> neighborTextStyle(const ResolvedParagraph &paragraph, size_t index) {
        if (index > 0 && !paragraph.runs[index - 1].attachment) {
            return paragraph.runs[index - 1].style;
        }

        if (index + 1 < paragraph.runs.size() && !paragraph.runs[index + 1].attachment) {
            return paragraph.runs[index + 1].style;
        }

        return std::nullopt;
    }

    void addAttachment(
        CFMutableDictionaryRef attributes,
        uint32_t attachment,
        uint32_t styleIndex,
        std::optional<uint32_t> neighborStyle
    ) {
        const ResolvedTextStyle &style = resolved_.styles[styleIndex];
        const AttachmentDescriptor &descriptor = document_.attachments()[attachment];
        std::optional<std::pair<double, double>> contentSize;

        if (auto found = container_.attachmentContentSizes.find(attachment);
            found != container_.attachmentContentSizes.end()) {
            contentSize = found->second;
        }

        AttachmentMetrics metrics;
        bool unsized = descriptor.pipeline == ImagePipeline::AsyncImage
            && descriptor.sizeKind == AttachmentSizeKind::Adaptive && !contentSize
            && !(descriptor.contentWidth && descriptor.contentHeight);

        if (unsized) {
            // An AsyncImage with no size yet is a zero-width placeholder as
            // tall as the adjacent character, so the line keeps its height
            // until the image arrives. Without adjacent text, the default
            // font sizes it.
            CTFontRef font = neighborStyle
                ? fonts_.font(resolved_.styles[*neighborStyle].font)
                : fonts_.defaultFont.get();
            double offset = neighborStyle ? resolved_.styles[*neighborStyle].baselineOffset : 0;
            double descent = CTFontGetDescent(font);
            metrics.width = 0;
            metrics.height = CTFontGetAscent(font) + descent;
            metrics.originY = offset - descent;
        } else {
            metrics = measureAttachment(descriptor, contentSize, fonts_.font(style.font), container_.width);
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
        CFDictionarySetValue(attributes, kCTRunDelegateAttributeName, delegate.get());
        CFDictionarySetValue(
            attributes,
            kAttachmentAttribute,
            makeNumber(static_cast<int32_t>(attachment)).get()
        );
    }

    LineMetrics metrics(CTLineRef line) const {
        LineMetrics result;
        CFArrayRef runs = CTLineGetGlyphRuns(line);
        CFIndex count = CFArrayGetCount(runs);

        for (CFIndex index = 0; index < count; ++index) {
            auto run = static_cast<CTRunRef>(CFArrayGetValueAtIndex(runs, index));
            CFDictionaryRef attributes = CTRunGetAttributes(run);
            auto style = intAttribute(attributes, kStyleAttribute).value_or(0);
            double offset = resolved_.styles[style].baselineOffset;

            CGFloat ascent = 0;
            CGFloat descent = 0;
            CGFloat leading = 0;

            if (CFDictionaryContainsKey(attributes, kAttachmentAttribute)) {
                CTRunGetTypographicBounds(run, CFRangeMake(0, 0), &ascent, &descent, &leading);
            } else {
                // Typographic height comes from the declared font even when
                // CoreText substitutes a fallback font, so lines keep the
                // default height; the fallback glyphs' real extent is
                // captured as ink bounds.
                CTFontRef declared = fonts_.font(resolved_.styles[style].font);
                ascent = CTFontGetAscent(declared);
                descent = CTFontGetDescent(declared);
                leading = CTFontGetLeading(declared);
                addInkBounds(
                    run,
                    static_cast<CTFontRef>(CFDictionaryGetValue(attributes, kCTFontAttributeName)),
                    offset,
                    result
                );
            }

            result.ascent = std::max(result.ascent, ascent + offset);
            result.descent = std::max(result.descent, descent - offset);
            result.leading = std::max(result.leading, static_cast<double>(leading));
        }

        if (count == 0) {
            CGFloat ascent = 0;
            CGFloat descent = 0;
            CGFloat leading = 0;
            CTLineGetTypographicBounds(line, &ascent, &descent, &leading);
            result.ascent = ascent;
            result.descent = descent;
            result.leading = leading;
        }

        return result;
    }

    LineMetrics fontMetrics(uint32_t styleIndex) const {
        const ResolvedTextStyle &style = resolved_.styles[styleIndex];
        CTFontRef font = fonts_.font(style.font);
        LineMetrics result;
        result.ascent = CTFontGetAscent(font) + style.baselineOffset;
        result.descent = CTFontGetDescent(font) - style.baselineOffset;
        result.leading = CTFontGetLeading(font);
        return result;
    }

    double flush(const ResolvedParagraphStyle &style) const {
        switch (style.alignment) {
        case TextAlignment::Left:
            return 0;
        case TextAlignment::Right:
            return 1;
        case TextAlignment::Center:
            return 0.5;
        case TextAlignment::Natural:
        case TextAlignment::Justified:
            return style.direction == WritingDirection::RightToLeft ? 1 : 0;
        }

        return 0;
    }

    // Positions `line` horizontally and fills in its metrics. Justified
    // paragraphs justify every line except the last.
    void place(Line &line, bool lastInParagraph) {
        const ResolvedParagraph &paragraph = resolved_.paragraphs[line.paragraph];
        LineMetrics lineMetrics;

        if (line.line) {
            if (paragraph.style.alignment == TextAlignment::Justified && !lastInParagraph
                && finiteWidth_) {
                if (CTLineRef justified = CTLineCreateJustifiedLine(
                        line.line.get(),
                        1.0,
                        container_.width
                    )) {
                    line.line = CFRef<CTLineRef>::adopt(justified);
                }
            }

            lineMetrics = metrics(line.line.get());
            double width = CTLineGetTypographicBounds(line.line.get(), nullptr, nullptr, nullptr);
            line.width = std::max(0.0, width - CTLineGetTrailingWhitespaceWidth(line.line.get()));
            line.x = finiteWidth_
                ? CTLineGetPenOffsetForFlush(line.line.get(), flush(paragraph.style), container_.width)
                : 0;
        } else {
            lineMetrics = fontMetrics(paragraph.paragraphTextStyle);
            line.width = 0;
            line.x = finiteWidth_ ? flush(paragraph.style) * container_.width : 0;
        }

        line.inkAscent = lineMetrics.inkAscent;
        line.inkDescent = lineMetrics.inkDescent;

        if (container_.lineHeightMode == LineHeightMode::GlyphBounds) {
            lineMetrics.ascent = std::max(lineMetrics.ascent, lineMetrics.inkAscent);
            lineMetrics.descent = std::max(lineMetrics.descent, lineMetrics.inkDescent);
        }

        line.ascent = lineMetrics.ascent;
        line.descent = lineMetrics.descent;
        line.leading = lineMetrics.leading;
        line.baseline = line.top + line.ascent;
    }

    // Returns false when the line does not fit the container's limits.
    bool commit(Line line, bool lastInParagraph, double spacingBefore) {
        if (container_.maxLines > 0 && layout_->lines.size() >= container_.maxLines) {
            return false;
        }

        line.top = layout_->lines.empty() ? 0 : cursor_ + spacingBefore;
        place(line, lastInParagraph);

        if (line.bottom() > container_.maxHeight) {
            return false;
        }

        cursor_ = line.bottom();
        layout_->lines.push_back(std::move(line));
        return true;
    }

    void breakLines() {
        double spacingBefore = 0;

        for (uint32_t index = 0; index < resolved_.paragraphs.size(); ++index) {
            const ResolvedParagraph &paragraph = resolved_.paragraphs[index];

            if (index > 0) {
                spacingBefore = resolved_.paragraphs[index - 1].style.paragraphSpacing;
            }

            if (paragraph.text.empty()) {
                Line line;
                line.paragraph = index;

                if (!commit(std::move(line), true, spacingBefore)) {
                    truncateLastLine();
                    return;
                }

                continue;
            }

            ParagraphText &text = paragraphText(index);
            auto length = static_cast<CFIndex>(paragraph.text.size());
            CFIndex start = 0;

            while (start < length) {
                CFIndex count = CTTypesetterSuggestLineBreak(text.typesetter.get(), start, breakWidth_);
                count = std::max<CFIndex>(count, 1);

                Line line;
                line.line = CFRef<CTLineRef>::adopt(
                    CTTypesetterCreateLine(text.typesetter.get(), CFRangeMake(start, count))
                );
                line.paragraph = index;
                line.location = static_cast<uint32_t>(start);
                line.length = static_cast<uint32_t>(count);

                if (!commit(std::move(line), start + count >= length, spacingBefore)) {
                    truncateLastLine();
                    return;
                }

                start += count;
                spacingBefore = paragraph.style.lineSpacing;
            }
        }
    }

    // Called when content remains after the last committed line.
    void truncateLastLine() {
        layout_->truncated = true;

        if (layout_->lines.empty()) {
            return;
        }

        Line &line = layout_->lines.back();
        const ResolvedParagraph &paragraph = resolved_.paragraphs[line.paragraph];
        auto token = CFRef<CFStringRef>::adopt(CFStringCreateWithCharacters(
            nullptr,
            reinterpret_cast<const UniChar *>(container_.truncationToken.data()),
            static_cast<CFIndex>(container_.truncationToken.size())
        ));
        CFRef<CFMutableDictionaryRef> tokenAttributes;
        CFRef<CTLineRef> source;

        if (!line.line) {
            tokenAttributes = makeAttributes(paragraph.paragraphTextStyle);
            auto string = CFRef<CFAttributedStringRef>::adopt(
                CFAttributedStringCreate(nullptr, token.get(), tokenAttributes.get())
            );
            source = CFRef<CTLineRef>::adopt(CTLineCreateWithAttributedString(string.get()));
        } else {
            ParagraphText &text = paragraphText(line.paragraph);
            CFIndex lineEnd = line.location + line.length;
            CFDictionaryRef last = CFAttributedStringGetAttributes(
                text.string.get(),
                lineEnd - 1,
                nullptr
            );
            tokenAttributes = CFRef<CFMutableDictionaryRef>::adopt(
                CFDictionaryCreateMutableCopy(nullptr, 0, last)
            );
            CFDictionaryRemoveValue(tokenAttributes.get(), kCTRunDelegateAttributeName);
            CFDictionaryRemoveValue(tokenAttributes.get(), kAttachmentAttribute);

            if (lineEnd < static_cast<CFIndex>(paragraph.text.size())) {
                source = CFRef<CTLineRef>::adopt(CTTypesetterCreateLine(
                    text.typesetter.get(),
                    CFRangeMake(line.location, paragraph.text.size() - line.location)
                ));
            } else {
                // The paragraph ends here but later content was cut, so the
                // token follows the line's own text.
                auto combined = CFRef<CFMutableAttributedStringRef>::adopt(
                    CFAttributedStringCreateMutableCopy(nullptr, 0, text.string.get())
                );
                CFAttributedStringReplaceString(
                    combined.get(),
                    CFRangeMake(lineEnd, CFAttributedStringGetLength(combined.get()) - lineEnd),
                    CFSTR("")
                );
                CFAttributedStringReplaceString(combined.get(), CFRangeMake(lineEnd, 0), token.get());
                CFAttributedStringSetAttributes(
                    combined.get(),
                    CFRangeMake(lineEnd, CFStringGetLength(token.get())),
                    tokenAttributes.get(),
                    true
                );
                auto typesetter = CFRef<CTTypesetterRef>::adopt(
                    CTTypesetterCreateWithAttributedString(combined.get())
                );
                source = CFRef<CTLineRef>::adopt(CTTypesetterCreateLine(
                    typesetter.get(),
                    CFRangeMake(line.location, CFAttributedStringGetLength(combined.get()) - line.location)
                ));
            }
        }

        auto tokenString = CFRef<CFAttributedStringRef>::adopt(
            CFAttributedStringCreate(nullptr, token.get(), tokenAttributes.get())
        );
        auto tokenLine = CFRef<CTLineRef>::adopt(CTLineCreateWithAttributedString(tokenString.get()));
        CTLineRef truncated = CTLineCreateTruncatedLine(
            source.get(),
            breakWidth_,
            kCTLineTruncationEnd,
            tokenLine.get()
        );

        if (!truncated) {
            return;
        }

        line.line = CFRef<CTLineRef>::adopt(truncated);
        line.truncated = true;
        place(line, true);
        cursor_ = line.bottom();
    }

    uint32_t joinGroup(int32_t gradient, const Line &line, uint32_t lineIndex, const Rect &rect) {
        GradientScope scope = document_.gradients()[gradient].scope;
        uint32_t instance = 0;

        switch (scope) {
        case GradientScope::Line:
            instance = lineIndex;
            break;
        case GradientScope::Paragraph:
            instance = line.paragraph;
            break;
        case GradientScope::Document:
            instance = 0;
            break;
        }

        auto key = std::make_pair(gradient, instance);
        auto found = groupIndices_.find(key);

        if (found == groupIndices_.end()) {
            auto index = static_cast<uint32_t>(layout_->gradientGroups.size());
            layout_->gradientGroups.push_back({gradient, scope, instance, rect, 1});
            groupIndices_.emplace(key, index);
            return index;
        }

        GradientGroup &group = layout_->gradientGroups[found->second];
        double minX = std::min(group.rect.x, rect.x);
        double minY = std::min(group.rect.y, rect.y);
        double maxX = std::max(group.rect.x + group.rect.width, rect.x + rect.width);
        double maxY = std::max(group.rect.y + group.rect.height, rect.y + rect.height);
        group.rect = {minX, minY, maxX - minX, maxY - minY};
        group.memberCount += 1;
        return found->second;
    }

    void collectRuns() {
        for (uint32_t lineIndex = 0; lineIndex < layout_->lines.size(); ++lineIndex) {
            Line &line = layout_->lines[lineIndex];

            if (!line.line) {
                continue;
            }

            CFArrayRef runs = CTLineGetGlyphRuns(line.line.get());

            for (CFIndex index = 0; index < CFArrayGetCount(runs); ++index) {
                auto run = static_cast<CTRunRef>(CFArrayGetValueAtIndex(runs, index));
                CFIndex glyphCount = CTRunGetGlyphCount(run);

                if (glyphCount == 0) {
                    continue;
                }

                std::vector<CGPoint> positions(glyphCount);
                std::vector<CGSize> advances(glyphCount);
                CTRunGetPositions(run, CFRangeMake(0, 0), positions.data());
                CTRunGetAdvances(run, CFRangeMake(0, 0), advances.data());
                double minX = positions[0].x;
                double maxX = positions[0].x;

                for (CFIndex glyph = 0; glyph < glyphCount; ++glyph) {
                    minX = std::min(minX, static_cast<double>(positions[glyph].x));
                    maxX = std::max(maxX, static_cast<double>(positions[glyph].x + advances[glyph].width));
                }

                CFDictionaryRef attributes = CTRunGetAttributes(run);
                auto font = static_cast<CTFontRef>(CFDictionaryGetValue(attributes, kCTFontAttributeName));
                LineRun lineRun;
                lineRun.run = CFRef<CTRunRef>::retain(run);
                lineRun.style = static_cast<uint32_t>(intAttribute(attributes, kStyleAttribute).value_or(0));

                if (auto attachment = intAttribute(attributes, kAttachmentAttribute)) {
                    lineRun.attachment = static_cast<uint32_t>(*attachment);
                }

                lineRun.x = line.x + minX;
                lineRun.width = maxX - minX;
                lineRun.colorGlyphs = font && (CTFontGetSymbolicTraits(font) & kCTFontTraitColorGlyphs);
                line.runs.push_back(std::move(lineRun));
            }

            // Visual order, which underline merging relies on.
            std::sort(line.runs.begin(), line.runs.end(), [](const LineRun &a, const LineRun &b) {
                return a.x < b.x;
            });

            for (LineRun &lineRun : line.runs) {
                const ResolvedTextStyle &style = resolved_.styles[lineRun.style];
                addHitRegion(line, lineIndex, lineRun, style);
                Rect bounds = {
                    lineRun.x,
                    line.baseline - line.ascent,
                    lineRun.width,
                    line.ascent + line.descent,
                };

                if (lineRun.attachment) {
                    const AttachmentMetrics &metrics = attachmentMetrics_[*lineRun.attachment];
                    layout_->attachments.push_back({
                        *lineRun.attachment,
                        lineIndex,
                        {
                            lineRun.x,
                            line.baseline - style.baselineOffset - (metrics.originY + metrics.height),
                            metrics.width,
                            metrics.height,
                        },
                    });
                    continue;
                }

                if (style.foreground.kind == FillKind::Gradient) {
                    lineRun.fillGroup = joinGroup(style.foreground.index, line, lineIndex, bounds);
                }

                if (style.underline) {
                    addDecoration(line, lineIndex, lineRun, style, bounds);
                }
            }
        }
    }

    void addHitRegion(const Line &line, uint32_t lineIndex, const LineRun &lineRun, const ResolvedTextStyle &style) {
        if (style.interactionSet == kNoInteractionSet || lineRun.width <= 0) {
            return;
        }

        Rect rect = {lineRun.x, line.top, lineRun.width, line.bottom() - line.top};
        auto &regions = layout_->hitRegions;

        if (!regions.empty()) {
            HitRegion &previous = regions.back();

            if (previous.line == lineIndex && previous.interactionSet == style.interactionSet
                && std::fabs(previous.rect.x + previous.rect.width - rect.x) < kMergeTolerance) {
                previous.rect.width = rect.x + rect.width - previous.rect.x;
                return;
            }
        }

        regions.push_back({style.interactionSet, lineIndex, rect});
    }

    void addDecoration(
        const Line &line,
        uint32_t lineIndex,
        const LineRun &lineRun,
        const ResolvedTextStyle &style,
        const Rect &bounds
    ) {
        // Metrics come from the declared font, not a fallback font, so an
        // emoji inside underlined text does not split the segment.
        CTFontRef font = fonts_.font(style.font);
        double thickness = style.underline->thickness.value_or(CTFontGetUnderlineThickness(font));

        if (thickness <= 0) {
            thickness = 1;
        }

        DecorationSegment segment;
        segment.line = lineIndex;
        segment.minX = lineRun.x;
        segment.maxX = lineRun.x + lineRun.width;
        segment.centerY = line.baseline - style.baselineOffset - CTFontGetUnderlinePosition(font);
        segment.thickness = thickness;
        segment.underline = *style.underline;
        segment.fill = *style.underlineFill;

        if (segment.fill.kind == FillKind::Gradient) {
            segment.group = lineRun.fillGroup && style.foreground == segment.fill
                ? lineRun.fillGroup
                : std::optional<uint32_t>(joinGroup(segment.fill.index, line, lineIndex, bounds));
        }

        auto &decorations = layout_->decorations;

        if (!decorations.empty()) {
            DecorationSegment &previous = decorations.back();

            if (previous.line == lineIndex && std::fabs(previous.maxX - segment.minX) < kMergeTolerance
                && previous.underline == segment.underline && previous.fill == segment.fill
                && previous.thickness == segment.thickness && previous.centerY == segment.centerY) {
                previous.maxX = std::max(previous.maxX, segment.maxX);
                return;
            }
        }

        decorations.push_back(segment);
    }

    void measure() {
        double width = 0;

        for (const Line &line : layout_->lines) {
            width = std::max(width, line.x + line.width);
        }

        layout_->width = finiteWidth_ ? std::min(width, container_.width) : width;
        layout_->height = layout_->lines.empty() ? 0 : layout_->lines.back().bottom();
    }
};

} // namespace

std::shared_ptr<const Layout> computeLayout(
    const Document &document,
    const ResolvedDocument &resolved,
    const FontTable &fonts,
    const Container &container
) {
    return LayoutBuilder(document, resolved, fonts, container).run();
}

} // namespace atr
