// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#pragma once

#include <limits>
#include <optional>
#include <utility>
#include <vector>

#include "atr/layout/Layout.hpp"

namespace atr {

// Which visual place an offset means when it has two: the end of one line
// and the start of the next at a soft break, or the two sides of a bidi
// boundary. Upstream belongs to the preceding character.
enum class Affinity : uint8_t {
    Upstream,
    Downstream,
};

struct TextPosition {
    uint32_t offset = 0;
    Affinity affinity = Affinity::Downstream;

    bool operator==(const TextPosition &) const = default;
};

struct TextRange {
    uint32_t location = 0;
    uint32_t length = 0;

    uint32_t end() const { return location + length; }
    bool operator==(const TextRange &) const = default;
};

enum class Granularity : uint8_t {
    // One grapheme cluster.
    Character,
    Word,
    Sentence,
    Line,
    // Excludes the newline separator.
    Paragraph,
};

struct SelectionRect {
    Rect rect;
    uint32_t line = 0;
    bool rightToLeft = false;
    bool containsStart = false;
    bool containsEnd = false;
};

// Position and rect queries over one layout. Offsets are document-global
// UTF-16 units, where paragraphs are joined by one newline and each
// attachment is one U+FFFC; geometry is in layout coordinates. Holds only
// references, so it is cheap to make per query, and safe on any thread.
class TextGeometry {
public:
    TextGeometry(const ResolvedDocument &resolved, const Layout &layout);

    uint32_t textLength() const;
    // The drawn text; excludes text cut by truncation or container limits.
    TextRange visibleRange() const;
    TextRange lineRange(size_t line) const;

    // A point in the gap between lines is on no line.
    std::optional<size_t> lineAtY(double y) const;
    // Nil for an offset past the visible text.
    std::optional<size_t> lineContaining(TextPosition position) const;
    // Lines whose typographic frames overlap [minY, maxY), as [first, end).
    std::pair<size_t, size_t> linesBetween(double minY, double maxY) const;

    // The grapheme cluster under the point; nil off glyphs, in line gaps,
    // and on a truncation token.
    std::optional<uint32_t> characterIndex(double x, double y) const;
    // Snaps to the nearest line and to grapheme boundaries.
    TextPosition closestPosition(double x, double y) const;

    // Zero width and the line's typographic height. A hidden offset sits
    // before the truncation token. Carets and rects stay inside a finite
    // container width, although trailing whitespace may hang past it.
    Rect caretRect(TextPosition position) const;
    // Only the visible part of `range` produces rects. Newline separators
    // and empty lines produce none.
    std::vector<SelectionRect> selectionRects(
        TextRange range,
        double minY = -std::numeric_limits<double>::infinity(),
        double maxY = std::numeric_limits<double>::infinity()
    ) const;
    std::optional<Rect> boundingRect(TextRange range) const;

    // Nil past the end of the text, and for word, sentence, or character
    // at the end of the text; a separator is its own character.
    std::optional<TextRange> rangeEnclosing(uint32_t offset, Granularity granularity) const;

private:
    const ResolvedDocument &resolved_;
    const Layout &layout_;

    uint32_t lineStart(size_t line) const;
    uint32_t lineEnd(size_t line) const;
    bool endsParagraph(size_t line) const;
    // Keeps geometry inside a finite container.
    double clampX(double x) const;
    size_t paragraphContaining(uint32_t offset) const;
    TextPosition positionInLine(size_t line, double x) const;
    double caretX(size_t line, uint32_t local, Affinity affinity) const;
};

} // namespace atr
