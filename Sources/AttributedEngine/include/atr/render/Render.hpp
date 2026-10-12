// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#pragma once

#include <CoreGraphics/CoreGraphics.h>

#include "atr/layout/Layout.hpp"

namespace atr {

// Everything drawing needs besides the layout, resolved on the main thread
// for one appearance and then safe to use on any thread.
struct RenderResources {
    // Indexed like the facade's color table.
    std::vector<CFRef<CGColorRef>> colors;
    // Indexed by attachment ID; empty entries are not loaded yet.
    std::vector<CFRef<CGImageRef>> images;
    // Color glyphs such as emoji keep their own colors unless this is set.
    bool gradientsIncludeColorGlyphs = false;
};

// Draws the part of `layout` that intersects `clip`. The context must use
// layout coordinates: top-left origin, y growing downward, in points.
void render(
    CGContextRef context,
    const Layout &layout,
    const Document &document,
    const ResolvedDocument &resolved,
    const RenderResources &resources,
    const Rect &clip
);

} // namespace atr
