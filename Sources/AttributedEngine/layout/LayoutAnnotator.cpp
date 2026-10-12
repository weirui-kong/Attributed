// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#include "LayoutAnnotator.hpp"

namespace atr::layout {

LayoutAnnotator::LayoutAnnotator(const LayoutContext &context, const Typesetter &typesetter, Layout &layout)
    : context_(context), typesetter_(typesetter), layout_(layout) {}

void LayoutAnnotator::run() {
    for (uint32_t lineIndex = 0; lineIndex < layout_.lines.size(); ++lineIndex) {
        Line &line = layout_.lines[lineIndex];

        if (!line.line) {
            continue;
        }

        collectRuns(line);

        for (LineRun &lineRun : line.runs) {
            const ResolvedTextStyle &style = context_.resolved.styles[lineRun.style];
            addHitRegion(line, lineIndex, lineRun, style);
            Rect bounds = {lineRun.x, line.baseline - line.ascent, lineRun.width, line.ascent + line.descent};

            if (lineRun.attachment) {
                const AttachmentMetrics &metrics = typesetter_.attachmentMetrics(*lineRun.attachment);
                layout_.attachments.push_back({
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

    measure();
}

void LayoutAnnotator::collectRuns(Line &line) {
    CFArrayRef runs = CTLineGetGlyphRuns(line.line.get());

    for (CFIndex index = 0; index < CFArrayGetCount(runs); ++index) {
        auto run = static_cast<CTRunRef>(CFArrayGetValueAtIndex(runs, index));
        CFIndex glyphCount = CTRunGetGlyphCount(run);

        if (glyphCount == 0) {
            continue;
        }

        // Glyph order within a run need not be visual, so the extent comes
        // from every glyph.
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

    // Visual order, which hit-region and underline merging rely on.
    std::sort(line.runs.begin(), line.runs.end(), [](const LineRun &a, const LineRun &b) {
        return a.x < b.x;
    });
}

uint32_t LayoutAnnotator::joinGroup(int32_t gradient, const Line &line, uint32_t lineIndex, const Rect &rect) {
    GradientScope scope = context_.document.gradients()[gradient].scope;
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
        auto index = static_cast<uint32_t>(layout_.gradientGroups.size());
        layout_.gradientGroups.push_back({gradient, scope, instance, rect, 1});
        groupIndices_.emplace(key, index);
        return index;
    }

    GradientGroup &group = layout_.gradientGroups[found->second];
    double minX = std::min(group.rect.x, rect.x);
    double minY = std::min(group.rect.y, rect.y);
    double maxX = std::max(group.rect.x + group.rect.width, rect.x + rect.width);
    double maxY = std::max(group.rect.y + group.rect.height, rect.y + rect.height);
    group.rect = {minX, minY, maxX - minX, maxY - minY};
    group.memberCount += 1;
    return found->second;
}

void LayoutAnnotator::addHitRegion(
    const Line &line,
    uint32_t lineIndex,
    const LineRun &run,
    const ResolvedTextStyle &style
) {
    if (style.interactionSet == kNoInteractionSet || run.width <= 0) {
        return;
    }

    Rect rect = {run.x, line.top, run.width, line.bottom() - line.top};
    auto &regions = layout_.hitRegions;

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

void LayoutAnnotator::addDecoration(
    const Line &line,
    uint32_t lineIndex,
    const LineRun &run,
    const ResolvedTextStyle &style,
    const Rect &bounds
) {
    // Metrics come from the declared font, not a fallback font, so an emoji
    // inside underlined text does not split the segment.
    CTFontRef font = context_.fonts.font(style.font);
    double thickness = style.underline->thickness.value_or(CTFontGetUnderlineThickness(font));

    DecorationSegment segment;
    segment.line = lineIndex;
    segment.minX = run.x;
    segment.maxX = run.x + run.width;
    segment.centerY = line.baseline - style.baselineOffset - CTFontGetUnderlinePosition(font);
    segment.thickness = thickness > 0 ? thickness : 1;
    segment.underline = *style.underline;
    segment.fill = *style.underlineFill;

    if (segment.fill.kind == FillKind::Gradient) {
        segment.group = run.fillGroup && style.foreground == segment.fill
            ? run.fillGroup
            : std::optional<uint32_t>(joinGroup(segment.fill.index, line, lineIndex, bounds));
    }

    auto &decorations = layout_.decorations;

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

void LayoutAnnotator::measure() {
    double width = 0;

    for (const Line &line : layout_.lines) {
        width = std::max(width, line.x + line.width);
    }

    layout_.width = context_.finiteWidth ? std::min(width, context_.container.width) : width;
    layout_.height = layout_.lines.empty() ? 0 : layout_.lines.back().bottom();
}

} // namespace atr::layout
