// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#include "LineBreaker.hpp"

namespace atr::layout {

namespace {

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
    CTFontGetBoundingRectsForGlyphs(font, kCTFontOrientationHorizontal, glyphs.data(), rects.data(), count);

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

LineMetrics lineMetrics(const LayoutContext &context, CTLineRef line) {
    LineMetrics result;
    CFArrayRef runs = CTLineGetGlyphRuns(line);
    CFIndex count = CFArrayGetCount(runs);

    for (CFIndex index = 0; index < count; ++index) {
        auto run = static_cast<CTRunRef>(CFArrayGetValueAtIndex(runs, index));
        CFDictionaryRef attributes = CTRunGetAttributes(run);
        const ResolvedTextStyle &style = context.resolved.styles[intAttribute(attributes, kStyleAttribute).value_or(0)];
        CGFloat ascent = 0;
        CGFloat descent = 0;
        CGFloat leading = 0;

        if (CFDictionaryContainsKey(attributes, kAttachmentAttribute)) {
            CTRunGetTypographicBounds(run, CFRangeMake(0, 0), &ascent, &descent, &leading);
        } else {
            // Typographic height comes from the declared font even when
            // CoreText substitutes a fallback font, so lines keep the
            // default height; the fallback glyphs' real extent is captured
            // as ink bounds.
            CTFontRef declared = context.fonts.font(style.font);
            ascent = CTFontGetAscent(declared);
            descent = CTFontGetDescent(declared);
            leading = CTFontGetLeading(declared);
            addInkBounds(
                run,
                static_cast<CTFontRef>(CFDictionaryGetValue(attributes, kCTFontAttributeName)),
                style.baselineOffset,
                result
            );
        }

        result.ascent = std::max(result.ascent, ascent + style.baselineOffset);
        result.descent = std::max(result.descent, descent - style.baselineOffset);
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

LineMetrics fontMetrics(const LayoutContext &context, uint32_t styleIndex) {
    const ResolvedTextStyle &style = context.resolved.styles[styleIndex];
    CTFontRef font = context.fonts.font(style.font);
    LineMetrics result;
    result.ascent = CTFontGetAscent(font) + style.baselineOffset;
    result.descent = CTFontGetDescent(font) - style.baselineOffset;
    result.leading = CTFontGetLeading(font);
    return result;
}

double flush(const ResolvedParagraphStyle &style) {
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

// End of the paragraph text a truncated line shows, ignoring token runs.
// Run string ranges are not enough: with an empty token, CoreText keeps one
// run whose range still covers the cut text, so the end comes from the last
// glyph's character, widened to its whole composed sequence.
uint32_t visibleEnd(CTLineRef line, uint32_t location, const std::u16string &text) {
    CFArrayRef runs = CTLineGetGlyphRuns(line);
    std::optional<CFIndex> last;
    std::vector<CFIndex> indices;

    for (CFIndex index = 0; index < CFArrayGetCount(runs); ++index) {
        auto run = static_cast<CTRunRef>(CFArrayGetValueAtIndex(runs, index));

        if (CFDictionaryContainsKey(CTRunGetAttributes(run), kTruncationTokenAttribute)) {
            continue;
        }

        indices.resize(CTRunGetGlyphCount(run));
        CTRunGetStringIndices(run, CFRangeMake(0, 0), indices.data());

        for (CFIndex value : indices) {
            if (value < static_cast<CFIndex>(text.size())) {
                last = std::max(last.value_or(value), value);
            }
        }
    }

    if (!last) {
        return location;
    }

    auto string = CFRef<CFStringRef>::adopt(CFStringCreateWithCharactersNoCopy(
        nullptr,
        reinterpret_cast<const UniChar *>(text.data()),
        static_cast<CFIndex>(text.size()),
        kCFAllocatorNull
    ));
    CFRange sequence = CFStringGetRangeOfComposedCharactersAtIndex(string.get(), *last);
    return static_cast<uint32_t>(std::max<CFIndex>(location, sequence.location + sequence.length));
}

} // namespace

LineBreaker::LineBreaker(const LayoutContext &context, Typesetter &typesetter, Layout &layout)
    : context_(context), typesetter_(typesetter), layout_(layout) {}

void LineBreaker::reuse(const Layout &previous, std::vector<bool> dirtyParagraphs) {
    size_t paragraphCount = context_.resolved.paragraphs.size();
    std::vector<std::pair<size_t, size_t>> lines(paragraphCount, {0, 0});

    for (size_t index = 0; index < previous.lines.size(); ++index) {
        uint32_t paragraph = previous.lines[index].paragraph;

        if (paragraph >= paragraphCount) {
            return;
        }

        if (lines[paragraph].second == 0) {
            lines[paragraph].first = index;
        }

        lines[paragraph].second += 1;
    }

    previous_ = &previous;
    dirty_ = std::move(dirtyParagraphs);
    previousLines_ = std::move(lines);
}

// Copies the paragraph's lines from the previous layout, moved so the first
// one starts where breaking it again would have put it.
bool LineBreaker::reuseParagraph(uint32_t index, double spacingBefore) {
    if (!previous_ || dirty_[index] || previousLines_[index].second == 0) {
        return false;
    }

    auto [first, count] = previousLines_[index];
    double top = layout_.lines.empty() ? 0 : cursor_ + spacingBefore;
    double offset = top - previous_->lines[first].top;

    for (size_t line = first; line < first + count; ++line) {
        Line copy = previous_->lines[line];
        // Runs are collected again by the annotator.
        copy.runs.clear();
        copy.top += offset;
        copy.baseline += offset;
        layout_.lines.push_back(std::move(copy));
    }

    cursor_ = layout_.lines.back().bottom();
    return true;
}

void LineBreaker::run() {
    double spacingBefore = 0;
    const auto &paragraphs = context_.resolved.paragraphs;

    for (uint32_t index = 0; index < paragraphs.size(); ++index) {
        const ResolvedParagraph &paragraph = paragraphs[index];

        if (index > 0) {
            spacingBefore = paragraphs[index - 1].style.paragraphSpacing;
        }

        if (reuseParagraph(index, spacingBefore)) {
            continue;
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

        ParagraphText &text = typesetter_.paragraph(index);
        auto length = static_cast<CFIndex>(paragraph.text.size());
        CFIndex start = 0;

        while (start < length) {
            CFIndex count = CTTypesetterSuggestLineBreak(text.typesetter.get(), start, context_.breakWidth);
            count = std::max<CFIndex>(count, 1);

            Line line;
            line.line = CFRef<CTLineRef>::adopt(CTTypesetterCreateLine(text.typesetter.get(), CFRangeMake(start, count)));
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

// Returns false when the line does not fit the container's limits.
bool LineBreaker::commit(Line line, bool lastInParagraph, double spacingBefore) {
    const Container &container = context_.container;

    if (container.maxLines > 0 && layout_.lines.size() >= container.maxLines) {
        return false;
    }

    line.top = layout_.lines.empty() ? 0 : cursor_ + spacingBefore;
    place(line, lastInParagraph);

    if (line.bottom() > container.maxHeight) {
        return false;
    }

    cursor_ = line.bottom();
    layout_.lines.push_back(std::move(line));
    return true;
}

// Positions `line` horizontally and fills in its metrics. Justified
// paragraphs justify every line except the last.
void LineBreaker::place(Line &line, bool lastInParagraph) const {
    const ResolvedParagraph &paragraph = context_.resolved.paragraphs[line.paragraph];
    double width = context_.container.width;
    LineMetrics metrics;

    if (line.line) {
        if (paragraph.style.alignment == TextAlignment::Justified && !lastInParagraph && context_.finiteWidth) {
            if (CTLineRef justified = CTLineCreateJustifiedLine(line.line.get(), 1.0, width)) {
                line.line = CFRef<CTLineRef>::adopt(justified);
            }
        }

        metrics = lineMetrics(context_, line.line.get());
        double lineWidth = CTLineGetTypographicBounds(line.line.get(), nullptr, nullptr, nullptr);
        line.width = std::max(0.0, lineWidth - CTLineGetTrailingWhitespaceWidth(line.line.get()));
        line.x = context_.finiteWidth
            ? CTLineGetPenOffsetForFlush(line.line.get(), flush(paragraph.style), width)
            : 0;
    } else {
        metrics = fontMetrics(context_, paragraph.paragraphTextStyle);
        line.width = 0;
        line.x = context_.finiteWidth ? flush(paragraph.style) * width : 0;
    }

    line.inkAscent = metrics.inkAscent;
    line.inkDescent = metrics.inkDescent;

    if (context_.container.lineHeightMode == LineHeightMode::GlyphBounds) {
        metrics.ascent = std::max(metrics.ascent, metrics.inkAscent);
        metrics.descent = std::max(metrics.descent, metrics.inkDescent);
    }

    line.ascent = metrics.ascent;
    line.descent = metrics.descent;
    line.leading = metrics.leading;
    line.baseline = line.top + line.ascent;
}

// Called when content remains after the last committed line.
void LineBreaker::truncateLastLine() {
    layout_.truncated = true;

    if (layout_.lines.empty()) {
        return;
    }

    Line &line = layout_.lines.back();
    const ResolvedParagraph &paragraph = context_.resolved.paragraphs[line.paragraph];
    const std::u16string &tokenText = context_.container.truncationToken;
    auto token = CFRef<CFStringRef>::adopt(CFStringCreateWithCharacters(
        nullptr,
        reinterpret_cast<const UniChar *>(tokenText.data()),
        static_cast<CFIndex>(tokenText.size())
    ));
    CFRef<CFMutableDictionaryRef> tokenAttributes;
    CFRef<CTLineRef> source;

    if (!line.line) {
        tokenAttributes = typesetter_.attributes(paragraph.paragraphTextStyle);
        CFDictionarySetValue(tokenAttributes.get(), kTruncationTokenAttribute, kCFBooleanTrue);
        auto string = CFRef<CFAttributedStringRef>::adopt(
            CFAttributedStringCreate(nullptr, token.get(), tokenAttributes.get())
        );
        source = CFRef<CTLineRef>::adopt(CTLineCreateWithAttributedString(string.get()));
    } else {
        ParagraphText &text = typesetter_.paragraph(line.paragraph);
        CFIndex lineEnd = line.location + line.length;
        CFDictionaryRef last = CFAttributedStringGetAttributes(text.string.get(), lineEnd - 1, nullptr);
        tokenAttributes = CFRef<CFMutableDictionaryRef>::adopt(CFDictionaryCreateMutableCopy(nullptr, 0, last));
        CFDictionaryRemoveValue(tokenAttributes.get(), kCTRunDelegateAttributeName);
        CFDictionaryRemoveValue(tokenAttributes.get(), kAttachmentAttribute);
        CFDictionarySetValue(tokenAttributes.get(), kTruncationTokenAttribute, kCFBooleanTrue);

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
            auto typesetter = CFRef<CTTypesetterRef>::adopt(CTTypesetterCreateWithAttributedString(combined.get()));
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
        context_.breakWidth,
        kCTLineTruncationEnd,
        tokenLine.get()
    );

    if (!truncated) {
        return;
    }

    line.line = CFRef<CTLineRef>::adopt(truncated);
    line.truncated = true;
    // Truncation may keep fewer characters than the line had, or more when
    // the line broke early at a word boundary.
    line.length = visibleEnd(truncated, line.location, paragraph.text) - line.location;
    place(line, true);
    cursor_ = line.bottom();
}

} // namespace atr::layout
