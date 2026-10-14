// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#pragma once

#include <vector>

#include "atr/layout/Layout.hpp"

namespace atr {

// Font identity used in glyph atoms for attachments; real fonts get ids from 1.
constexpr uint32_t kAttachmentAtomFont = 0;

// One drawn glyph or attachment: the unit a text transition moves, fades,
// and blurs on its own.
struct GlyphAtom {
    // Atoms with equal `font` and `glyph` draw the same shape, also across
    // layouts of different documents. For an attachment, `font` is
    // kAttachmentAtomFont and `glyph` the attachment ID.
    uint32_t font = 0;
    uint32_t glyph = 0;
    // Pen position on the baseline, in layout coordinates.
    double x = 0;
    double baseline = 0;
    double advance = 0;
    // The part of the drawing this atom owns. Tiles of one layout never
    // overlap, sit on the pixel grid of the scale they were made for, and
    // together cover everything drawn. Zero-advance glyphs such as combining
    // marks get an empty tile: their ink belongs to the glyph they sit on.
    Rect tile;
    // Middle of the font's typographic box, relative to the baseline, y down.
    double midline = 0;
    // The glyph's ink height, at least the font's cap height, so marks and
    // punctuation move as far as the letters and digits around them.
    double inkHeight = 0;
    // A decimal digit, or a "." or "," next to one.
    bool numeric = false;
};

// Atoms line by line, left to right within a line. Safe on any thread.
std::vector<GlyphAtom> glyphAtoms(const Layout &layout, const ResolvedDocument &resolved, double scale);

} // namespace atr
