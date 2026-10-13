// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#pragma once

#include "Typesetter.hpp"

namespace atr::layout {

// Breaks paragraphs into lines and places them top to bottom: line and
// paragraph spacing, line height (typographic or glyph bounds), alignment,
// and the container's height and line limits, truncating the last kept line
// when content is cut.
class LineBreaker {
public:
    LineBreaker(const LayoutContext &context, Typesetter &typesetter, Layout &layout);

    // Takes the lines of every paragraph not marked dirty from `previous`
    // instead of breaking it again. Only valid without line or height limits.
    void reuse(const Layout &previous, std::vector<bool> dirtyParagraphs);
    void run();

private:
    const LayoutContext &context_;
    Typesetter &typesetter_;
    Layout &layout_;
    double cursor_ = 0;
    const Layout *previous_ = nullptr;
    std::vector<bool> dirty_;
    // Index of each paragraph's first line in `previous_`, and the count.
    std::vector<std::pair<size_t, size_t>> previousLines_;

    bool reuseParagraph(uint32_t index, double spacingBefore);

    bool commit(Line line, bool lastInParagraph, double spacingBefore);
    void place(Line &line, bool lastInParagraph) const;
    void truncateLastLine();
};

} // namespace atr::layout
