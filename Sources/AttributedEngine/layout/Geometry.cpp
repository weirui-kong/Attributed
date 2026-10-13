// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#include "atr/layout/Geometry.hpp"

#include "LayoutContext.hpp"

namespace atr {

namespace {

// Wraps the paragraph text without copying it.
CFRef<CFStringRef> makeString(const std::u16string &text) {
    return CFRef<CFStringRef>::adopt(CFStringCreateWithCharactersNoCopy(
        nullptr,
        reinterpret_cast<const UniChar *>(text.data()),
        static_cast<CFIndex>(text.size()),
        kCFAllocatorNull
    ));
}

struct GlyphSpan {
    double minX = 0;
    double maxX = 0;
    bool rightToLeft = false;
    bool containsStart = false;
    bool containsEnd = false;
};

// Calls `visit(stringIndex, minX, maxX, rightToLeft)` for every glyph with an
// advance in the line's text runs, in layout coordinates.
template <typename Visit>
void forEachGlyph(const Line &line, Visit visit) {
    std::vector<CGPoint> positions;
    std::vector<CGSize> advances;
    std::vector<CFIndex> indices;

    for (const LineRun &lineRun : line.runs) {
        if (lineRun.truncationToken) {
            continue;
        }

        CTRunRef run = lineRun.run.get();
        CFIndex count = CTRunGetGlyphCount(run);
        positions.resize(count);
        advances.resize(count);
        indices.resize(count);
        CTRunGetPositions(run, CFRangeMake(0, 0), positions.data());
        CTRunGetAdvances(run, CFRangeMake(0, 0), advances.data());
        CTRunGetStringIndices(run, CFRangeMake(0, 0), indices.data());
        bool rightToLeft = CTRunGetStatus(run) & kCTRunStatusRightToLeft;

        for (CFIndex glyph = 0; glyph < count; ++glyph) {
            // Combining marks have no advance and sit over their base glyph.
            if (advances[glyph].width <= 0) {
                continue;
            }

            double minX = line.x + positions[glyph].x;
            visit(static_cast<uint32_t>(indices[glyph]), minX, minX + advances[glyph].width, rightToLeft);
        }
    }
}

} // namespace

TextGeometry::TextGeometry(const ResolvedDocument &resolved, const Layout &layout)
    : resolved_(resolved), layout_(layout) {}

uint32_t TextGeometry::textLength() const {
    return resolved_.length();
}

TextRange TextGeometry::visibleRange() const {
    if (layout_.lines.empty()) {
        return {};
    }

    if (!layout_.truncated) {
        return {0, textLength()};
    }

    return {0, lineEnd(layout_.lines.size() - 1)};
}

TextRange TextGeometry::lineRange(size_t line) const {
    return {lineStart(line), layout_.lines.at(line).length};
}

uint32_t TextGeometry::lineStart(size_t line) const {
    const Line &value = layout_.lines[line];
    return resolved_.paragraphs[value.paragraph].start + value.location;
}

uint32_t TextGeometry::lineEnd(size_t line) const {
    return lineStart(line) + layout_.lines[line].length;
}

double TextGeometry::clampX(double x) const {
    double width = layout_.container.width;
    return std::isfinite(width) ? std::clamp(x, 0.0, width) : x;
}

bool TextGeometry::endsParagraph(size_t line) const {
    const auto &lines = layout_.lines;
    return !lines[line].truncated
        && (line + 1 == lines.size() || lines[line + 1].paragraph != lines[line].paragraph);
}

size_t TextGeometry::paragraphContaining(uint32_t offset) const {
    const auto &paragraphs = resolved_.paragraphs;
    auto found = std::upper_bound(
        paragraphs.begin(),
        paragraphs.end(),
        offset,
        [](uint32_t value, const ResolvedParagraph &paragraph) { return value < paragraph.start; }
    );
    return found == paragraphs.begin() ? 0 : static_cast<size_t>(found - paragraphs.begin() - 1);
}

std::optional<size_t> TextGeometry::lineAtY(double y) const {
    const auto &lines = layout_.lines;
    auto found = std::upper_bound(lines.begin(), lines.end(), y, [](double value, const Line &line) {
        return value < line.top;
    });

    if (found == lines.begin()) {
        return std::nullopt;
    }

    auto index = static_cast<size_t>(found - lines.begin() - 1);

    if (y >= lines[index].bottom()) {
        return std::nullopt;
    }

    return index;
}

std::optional<size_t> TextGeometry::lineContaining(TextPosition position) const {
    const auto &lines = layout_.lines;

    if (lines.empty() || position.offset > visibleRange().end()) {
        return std::nullopt;
    }

    size_t low = 0;
    size_t high = lines.size();

    // The last line starting at or before the offset.
    while (high - low > 1) {
        size_t middle = (low + high) / 2;

        if (lineStart(middle) <= position.offset) {
            low = middle;
        } else {
            high = middle;
        }
    }

    // At a soft break, upstream means the end of the earlier line.
    if (position.affinity == Affinity::Upstream && low > 0 && position.offset == lineStart(low)
        && lines[low - 1].paragraph == lines[low].paragraph && lineEnd(low - 1) == position.offset) {
        return low - 1;
    }

    return low;
}

std::pair<size_t, size_t> TextGeometry::linesBetween(double minY, double maxY) const {
    const auto &lines = layout_.lines;
    auto first = std::upper_bound(lines.begin(), lines.end(), minY, [](double value, const Line &line) {
        return value < line.bottom();
    });
    auto end = std::lower_bound(first, lines.end(), maxY, [](const Line &line, double value) {
        return line.top < value;
    });
    return {static_cast<size_t>(first - lines.begin()), static_cast<size_t>(end - lines.begin())};
}

std::optional<uint32_t> TextGeometry::characterIndex(double x, double y) const {
    std::optional<size_t> lineIndex = lineAtY(y);

    if (!lineIndex) {
        return std::nullopt;
    }

    const Line &line = layout_.lines[*lineIndex];
    std::optional<uint32_t> local;

    forEachGlyph(line, [&](uint32_t index, double minX, double maxX, bool) {
        if (!local && x >= minX && x < maxX && index >= line.location && index < line.location + line.length) {
            local = index;
        }
    });

    if (!local) {
        return std::nullopt;
    }

    const ResolvedParagraph &paragraph = resolved_.paragraphs[line.paragraph];
    auto string = makeString(paragraph.text);
    CFRange cluster = CFStringGetRangeOfComposedCharactersAtIndex(string.get(), *local);
    return paragraph.start + static_cast<uint32_t>(cluster.location);
}

TextPosition TextGeometry::closestPosition(double x, double y) const {
    const auto &lines = layout_.lines;

    if (lines.empty()) {
        return {};
    }

    std::optional<size_t> lineIndex = lineAtY(y);

    if (!lineIndex) {
        auto next = std::upper_bound(lines.begin(), lines.end(), y, [](double value, const Line &line) {
            return value < line.top;
        });

        if (next == lines.begin()) {
            lineIndex = 0;
        } else if (next == lines.end()) {
            lineIndex = lines.size() - 1;
        } else {
            auto below = static_cast<size_t>(next - lines.begin());
            double toAbove = y - lines[below - 1].bottom();
            double toBelow = lines[below].top - y;
            lineIndex = toBelow < toAbove ? below : below - 1;
        }
    }

    return positionInLine(*lineIndex, x);
}

TextPosition TextGeometry::positionInLine(size_t lineIndex, double x) const {
    const Line &line = layout_.lines[lineIndex];
    uint32_t start = line.location;
    uint32_t end = line.location + line.length;
    const ResolvedParagraph &paragraph = resolved_.paragraphs[line.paragraph];

    if (!line.line || line.length == 0) {
        return {paragraph.start + start, Affinity::Downstream};
    }

    double target = x - line.x;
    CFIndex index = CTLineGetStringIndexForPosition(line.line.get(), CGPointMake(target, 0));
    auto local = index == kCFNotFound ? start : std::clamp(static_cast<uint32_t>(index), start, end);

    // Never inside a grapheme cluster: take the nearer boundary.
    if (local > start && local < end) {
        auto string = makeString(paragraph.text);
        CFRange cluster = CFStringGetRangeOfComposedCharactersAtIndex(string.get(), local);

        if (static_cast<uint32_t>(cluster.location) != local) {
            auto before = static_cast<uint32_t>(cluster.location);
            auto after = static_cast<uint32_t>(cluster.location + cluster.length);
            double toBefore = std::fabs(CTLineGetOffsetForStringIndex(line.line.get(), before, nullptr) - target);
            double toAfter = std::fabs(CTLineGetOffsetForStringIndex(line.line.get(), after, nullptr) - target);
            local = toAfter < toBefore ? after : before;
        }
    }

    Affinity affinity = Affinity::Downstream;

    if (local == end && (!endsParagraph(lineIndex) || line.truncated)) {
        affinity = Affinity::Upstream;
    } else if (!line.truncated || local < end) {
        // At a bidi boundary, the side whose caret is nearer the point.
        CGFloat secondary = 0;
        CGFloat primary = CTLineGetOffsetForStringIndex(line.line.get(), local, &secondary);

        if (std::fabs(secondary - target) < std::fabs(primary - target)) {
            affinity = Affinity::Upstream;
        }
    }

    return {paragraph.start + local, affinity};
}

double TextGeometry::caretX(size_t lineIndex, uint32_t local, Affinity affinity) const {
    const Line &line = layout_.lines[lineIndex];

    if (!line.line) {
        return line.x;
    }

    uint32_t end = line.location + line.length;

    // The truncated line's own CTLine has no caret for the cut text, so the
    // caret follows the last shown character.
    if (line.truncated && local >= end) {
        if (line.length == 0) {
            return line.x;
        }

        std::optional<uint32_t> last;
        double edge = line.x;

        forEachGlyph(line, [&](uint32_t index, double minX, double maxX, bool rightToLeft) {
            if (index < end && (!last || index >= *last)) {
                last = index;
                edge = rightToLeft ? minX : maxX;
            }
        });

        return edge;
    }

    CGFloat secondary = 0;
    CGFloat primary = CTLineGetOffsetForStringIndex(line.line.get(), local, &secondary);
    return line.x + (affinity == Affinity::Upstream ? secondary : primary);
}

Rect TextGeometry::caretRect(TextPosition position) const {
    if (layout_.lines.empty()) {
        return {};
    }

    uint32_t visibleEnd = visibleRange().end();

    if (position.offset > visibleEnd) {
        position = {visibleEnd, Affinity::Upstream};
    }

    size_t lineIndex = *lineContaining(position);
    const Line &line = layout_.lines[lineIndex];
    uint32_t local = position.offset - resolved_.paragraphs[line.paragraph].start;
    double x = clampX(caretX(lineIndex, local, position.affinity));
    return {x, line.top, 0, line.bottom() - line.top};
}

std::vector<SelectionRect> TextGeometry::selectionRects(TextRange range, double minY, double maxY) const {
    std::vector<SelectionRect> result;
    uint32_t start = range.location;
    uint32_t end = std::min(range.end(), visibleRange().end());

    if (range.length == 0 || start >= end) {
        return result;
    }

    std::vector<GlyphSpan> spans;

    for (size_t lineIndex = *lineContaining({start, Affinity::Downstream}); lineIndex < layout_.lines.size();
         ++lineIndex) {
        const Line &line = layout_.lines[lineIndex];
        uint32_t lineFirst = lineStart(lineIndex);

        if (lineFirst >= end || line.top >= maxY) {
            break;
        }

        if (!line.line || line.bottom() <= minY) {
            continue;
        }

        uint32_t paragraphStart = resolved_.paragraphs[line.paragraph].start;
        uint32_t localStart = std::max(start, lineFirst) - paragraphStart;
        uint32_t localEnd = std::min(end, lineEnd(lineIndex)) - paragraphStart;

        if (localStart >= localEnd) {
            continue;
        }

        // The range's first and last characters mark the spans holding its
        // ends; tracked by string index so ligatures still match.
        bool startsHere = start >= lineFirst;
        bool endsHere = end <= lineEnd(lineIndex);
        std::optional<uint32_t> firstIndex;
        std::optional<uint32_t> lastIndex;
        size_t firstSpan = 0;
        size_t lastSpan = 0;
        spans.clear();

        forEachGlyph(line, [&](uint32_t index, double minX, double maxX, bool rightToLeft) {
            if (index < localStart || index >= localEnd) {
                return;
            }

            if (!firstIndex || index < *firstIndex) {
                firstIndex = index;
                firstSpan = spans.size();
            }

            if (!lastIndex || index >= *lastIndex) {
                lastIndex = index;
                lastSpan = spans.size();
            }

            spans.push_back({minX, maxX, rightToLeft, false, false});
        });

        if (spans.empty()) {
            continue;
        }

        spans[firstSpan].containsStart = startsHere;
        spans[lastSpan].containsEnd = endsHere;
        std::sort(spans.begin(), spans.end(), [](const GlyphSpan &a, const GlyphSpan &b) {
            return a.minX < b.minX;
        });

        GlyphSpan merged = spans.front();
        auto flush = [&] {
            // Whitespace at a soft break hangs past the container edge.
            merged.minX = clampX(merged.minX);
            merged.maxX = clampX(merged.maxX);
            result.push_back({
                {merged.minX, line.top, merged.maxX - merged.minX, line.bottom() - line.top},
                static_cast<uint32_t>(lineIndex),
                merged.rightToLeft,
                merged.containsStart,
                merged.containsEnd,
            });
        };

        for (size_t index = 1; index < spans.size(); ++index) {
            const GlyphSpan &span = spans[index];

            if (span.rightToLeft == merged.rightToLeft && span.minX <= merged.maxX + layout::kMergeTolerance) {
                merged.maxX = std::max(merged.maxX, span.maxX);
                merged.containsStart = merged.containsStart || span.containsStart;
                merged.containsEnd = merged.containsEnd || span.containsEnd;
            } else {
                flush();
                merged = span;
            }
        }

        flush();
    }

    return result;
}

std::optional<Rect> TextGeometry::boundingRect(TextRange range) const {
    std::vector<SelectionRect> rects = selectionRects(range);

    if (rects.empty()) {
        return std::nullopt;
    }

    Rect first = rects.front().rect;
    double minX = first.x;
    double minY = first.y;
    double maxX = first.x + first.width;
    double maxY = first.y + first.height;

    for (const SelectionRect &selection : rects) {
        const Rect &rect = selection.rect;
        minX = std::min(minX, rect.x);
        minY = std::min(minY, rect.y);
        maxX = std::max(maxX, rect.x + rect.width);
        maxY = std::max(maxY, rect.y + rect.height);
    }

    return Rect{minX, minY, maxX - minX, maxY - minY};
}

std::optional<TextRange> TextGeometry::rangeEnclosing(uint32_t offset, Granularity granularity) const {
    if (resolved_.paragraphs.empty() || offset > textLength()) {
        return std::nullopt;
    }

    const ResolvedParagraph &paragraph = resolved_.paragraphs[paragraphContaining(offset)];
    auto length = static_cast<uint32_t>(paragraph.text.size());
    uint32_t local = offset - paragraph.start;
    bool atSeparator = local == length;

    switch (granularity) {
    case Granularity::Paragraph:
        return TextRange{paragraph.start, length};
    case Granularity::Line: {
        std::optional<size_t> line = lineContaining({offset, Affinity::Downstream});
        return line ? std::optional<TextRange>(lineRange(*line)) : std::nullopt;
    }
    case Granularity::Character: {
        if (atSeparator) {
            return offset < textLength() ? std::optional<TextRange>(TextRange{offset, 1}) : std::nullopt;
        }

        auto string = makeString(paragraph.text);
        CFRange cluster = CFStringGetRangeOfComposedCharactersAtIndex(string.get(), local);
        return TextRange{
            paragraph.start + static_cast<uint32_t>(cluster.location),
            static_cast<uint32_t>(cluster.length),
        };
    }
    case Granularity::Word:
    case Granularity::Sentence: {
        if (atSeparator) {
            return std::nullopt;
        }

        auto string = makeString(paragraph.text);
        auto locale = CFRef<CFLocaleRef>::adopt(CFLocaleCopyCurrent());
        auto tokenizer = CFRef<CFStringTokenizerRef>::adopt(CFStringTokenizerCreate(
            nullptr,
            string.get(),
            CFRangeMake(0, static_cast<CFIndex>(length)),
            granularity == Granularity::Word ? kCFStringTokenizerUnitWordBoundary : kCFStringTokenizerUnitSentence,
            locale.get()
        ));

        if (CFStringTokenizerGoToTokenAtIndex(tokenizer.get(), local) == kCFStringTokenizerTokenNone) {
            return std::nullopt;
        }

        CFRange token = CFStringTokenizerGetCurrentTokenRange(tokenizer.get());
        return TextRange{
            paragraph.start + static_cast<uint32_t>(token.location),
            static_cast<uint32_t>(token.length),
        };
    }
    }

    return std::nullopt;
}

} // namespace atr
