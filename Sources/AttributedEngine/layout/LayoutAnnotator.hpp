// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#pragma once

#include <map>

#include "Typesetter.hpp"

namespace atr::layout {

// Derives everything drawing and interaction need from placed lines: runs in
// visual order, attachment frames, gradient groups per scope, merged
// underline segments, merged hit regions, and the final size.
class LayoutAnnotator {
public:
    LayoutAnnotator(const LayoutContext &context, const Typesetter &typesetter, Layout &layout);

    void run();

private:
    const LayoutContext &context_;
    const Typesetter &typesetter_;
    Layout &layout_;
    std::map<std::pair<int32_t, uint32_t>, uint32_t> groupIndices_;

    void collectRuns(Line &line);
    uint32_t joinGroup(int32_t gradient, const Line &line, uint32_t lineIndex, const Rect &rect);
    void addHitRegion(const Line &line, uint32_t lineIndex, const LineRun &run, const ResolvedTextStyle &style);
    void addDecoration(
        const Line &line,
        uint32_t lineIndex,
        const LineRun &run,
        const ResolvedTextStyle &style,
        const Rect &bounds
    );
    void measure();
};

} // namespace atr::layout
