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

    void run();

private:
    const LayoutContext &context_;
    Typesetter &typesetter_;
    Layout &layout_;
    double cursor_ = 0;

    bool commit(Line line, bool lastInParagraph, double spacingBefore);
    void place(Line &line, bool lastInParagraph) const;
    void truncateLastLine();
};

} // namespace atr::layout
