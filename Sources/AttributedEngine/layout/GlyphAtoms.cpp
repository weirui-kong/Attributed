// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#include "atr/layout/GlyphAtoms.hpp"

#include <cstdio>
#include <mutex>
#include <string>
#include <unordered_map>

#include "LayoutContext.hpp"

namespace atr {

namespace {

// Ids follow the font's name and size rather than the CTFont object, since
// every document converts its fonts on its own: the same digit in the old
// and the new text must compare equal.
uint32_t fontIdentity(CTFontRef font) {
    static std::mutex mutex;
    static std::unordered_map<std::string, uint32_t> identities;

    std::string key;

    if (auto name = CFRef<CFStringRef>::adopt(CTFontCopyPostScriptName(font))) {
        CFIndex length = CFStringGetMaximumSizeForEncoding(CFStringGetLength(name.get()), kCFStringEncodingUTF8) + 1;
        key.resize(static_cast<size_t>(length));

        if (CFStringGetCString(name.get(), key.data(), length, kCFStringEncodingUTF8)) {
            key.resize(std::char_traits<char>::length(key.c_str()));
        } else {
            key.clear();
        }
    }

    char size[32];
    std::snprintf(size, sizeof(size), "@%.3f", CTFontGetSize(font));
    key += size;

    std::lock_guard<std::mutex> lock(mutex);
    auto [entry, inserted] = identities.try_emplace(key, static_cast<uint32_t>(identities.size() + 1));
    return entry->second;
}

bool isDigit(char16_t character) {
    static CFCharacterSetRef digits = CFCharacterSetGetPredefined(kCFCharacterSetDecimalDigit);
    return CFCharacterSetIsCharacterMember(digits, character);
}

bool isNumeric(const std::u16string &text, size_t index) {
    if (index >= text.size()) {
        return false;
    }

    char16_t character = text[index];

    if (isDigit(character)) {
        return true;
    }

    if (character != u'.' && character != u',') {
        return false;
    }

    return (index > 0 && isDigit(text[index - 1])) || (index + 1 < text.size() && isDigit(text[index + 1]));
}

struct Item {
    GlyphAtom atom;
    bool hasInk = false;
    double inkMinX = 0;
    double inkMaxX = 0;
    double inkTop = 0;
    double inkBottom = 0;
    // Horizontal extent the tile must cover.
    double minX = 0;
    double maxX = 0;
};

void addTextRun(const Line &line, const LineRun &lineRun, const ResolvedDocument &resolved, std::vector<Item> &items) {
    CTRunRef run = lineRun.run.get();
    CFIndex count = CTRunGetGlyphCount(run);
    auto font = static_cast<CTFontRef>(CFDictionaryGetValue(CTRunGetAttributes(run), kCTFontAttributeName));

    if (count == 0 || !font) {
        return;
    }

    std::vector<CGGlyph> glyphs(count);
    std::vector<CGPoint> positions(count);
    std::vector<CGSize> advances(count);
    std::vector<CFIndex> indices(count);
    std::vector<CGRect> bounds(count);
    CTRunGetGlyphs(run, CFRangeMake(0, 0), glyphs.data());
    CTRunGetPositions(run, CFRangeMake(0, 0), positions.data());
    CTRunGetAdvances(run, CFRangeMake(0, 0), advances.data());
    CTRunGetStringIndices(run, CFRangeMake(0, 0), indices.data());
    CTFontGetBoundingRectsForGlyphs(font, kCTFontOrientationHorizontal, glyphs.data(), bounds.data(), count);

    uint32_t identity = fontIdentity(font);
    double ascent = CTFontGetAscent(font);
    double descent = CTFontGetDescent(font);
    double capHeight = CTFontGetCapHeight(font);
    double baseline = line.baseline - resolved.styles[lineRun.style].baselineOffset;
    const std::u16string &text = resolved.paragraphs[line.paragraph].text;

    for (CFIndex index = 0; index < count; ++index) {
        Item item;
        GlyphAtom &atom = item.atom;
        atom.font = identity;
        atom.glyph = glyphs[index];
        atom.x = line.x + positions[index].x;
        atom.baseline = baseline - positions[index].y;
        atom.advance = std::max<double>(0, advances[index].width);
        atom.midline = (descent - ascent) / 2;
        atom.inkHeight = std::max<double>(CGRectGetHeight(bounds[index]), capHeight);
        atom.numeric = !lineRun.truncationToken && isNumeric(text, static_cast<size_t>(indices[index]));

        item.hasInk = !CGRectIsEmpty(bounds[index]);

        if (item.hasInk) {
            item.inkMinX = atom.x + CGRectGetMinX(bounds[index]);
            item.inkMaxX = atom.x + CGRectGetMaxX(bounds[index]);
            item.inkTop = atom.baseline - CGRectGetMaxY(bounds[index]);
            item.inkBottom = atom.baseline - CGRectGetMinY(bounds[index]);
        }

        items.push_back(item);
    }
}

void addAttachmentRun(const Layout &layout, size_t lineIndex, const LineRun &lineRun, std::vector<Item> &items) {
    const Line &line = layout.lines[lineIndex];
    Item item;
    GlyphAtom &atom = item.atom;
    atom.font = kAttachmentAtomFont;
    atom.glyph = *lineRun.attachment;
    atom.x = lineRun.x;
    atom.baseline = line.baseline;
    atom.advance = lineRun.width;

    for (const AttachmentFrame &frame : layout.attachments) {
        if (frame.attachment == *lineRun.attachment && frame.line == lineIndex) {
            item.hasInk = frame.frame.width > 0 && frame.frame.height > 0;
            item.inkMinX = frame.frame.x;
            item.inkMaxX = frame.frame.x + frame.frame.width;
            item.inkTop = frame.frame.y;
            item.inkBottom = frame.frame.y + frame.frame.height;
            atom.midline = frame.frame.y + frame.frame.height / 2 - line.baseline;
            atom.inkHeight = frame.frame.height;
            break;
        }
    }

    items.push_back(item);
}

} // namespace

std::vector<GlyphAtom> glyphAtoms(const Layout &layout, const ResolvedDocument &resolved, double scale) {
    scale = scale > 0 ? scale : 1;
    // Antialiasing reaches a little past the ink bounds.
    const double margin = 2 / scale;
    auto snap = [scale](double value) { return std::round(value * scale) / scale; };

    struct LineSpan {
        size_t first = 0;
        size_t end = 0;
        double top = 0;
        double bottom = 0;
        double typographicBottom = 0;
    };

    std::vector<GlyphAtom> atoms;
    std::vector<LineSpan> spans;

    for (size_t lineIndex = 0; lineIndex < layout.lines.size(); ++lineIndex) {
        const Line &line = layout.lines[lineIndex];
        std::vector<Item> items;

        for (const LineRun &run : line.runs) {
            if (run.attachment) {
                addAttachmentRun(layout, lineIndex, run, items);
            } else {
                addTextRun(line, run, resolved, items);
            }
        }

        if (items.empty()) {
            continue;
        }

        // Glyph order within a run need not be visual.
        std::stable_sort(items.begin(), items.end(), [](const Item &a, const Item &b) {
            return a.atom.x < b.atom.x;
        });

        double top = line.drawnTop();
        double bottom = line.drawnBottom();
        double left = items.front().atom.x;
        double right = left;

        for (const LineRun &run : line.runs) {
            left = std::min(left, run.x);
            right = std::max(right, run.x + run.width);
        }

        for (Item &item : items) {
            item.minX = item.hasInk ? item.inkMinX : item.atom.x;
            item.maxX = item.hasInk ? item.inkMaxX : item.atom.x + item.atom.advance;

            if (item.hasInk) {
                top = std::min(top, item.inkTop);
                bottom = std::max(bottom, item.inkBottom);
            }
        }

        for (const DecorationSegment &segment : layout.decorations) {
            if (segment.line == lineIndex) {
                double extent = segment.underline.lines == UnderlineLines::Double ? segment.thickness * 1.5 : segment.thickness / 2;
                top = std::min(top, segment.centerY - extent);
                bottom = std::max(bottom, segment.centerY + extent);
            }
        }

        // Zero-advance glyphs lend their ink to the glyph they sit on, the
        // advancing glyph before them, else the one after.
        std::vector<size_t> advancing;

        for (size_t index = 0; index < items.size(); ++index) {
            if (items[index].atom.advance > 0) {
                advancing.push_back(index);
            }
        }

        if (advancing.empty()) {
            advancing.push_back(0);
        }

        for (size_t index = 0, owner = 0; index < items.size(); ++index) {
            while (owner + 1 < advancing.size() && advancing[owner + 1] <= index) {
                ++owner;
            }

            Item &target = items[advancing[owner]];

            if (&target != &items[index] && items[index].hasInk) {
                target.minX = std::min(target.minX, items[index].minX);
                target.maxX = std::max(target.maxX, items[index].maxX);
            }
        }

        // Each boundary sits in the gap between two neighbors' ink, or at the
        // pen position where their ink overlaps.
        std::vector<double> edges = {std::floor((std::min(left, items[advancing.front()].minX) - margin) * scale) / scale};

        for (size_t index = 1; index < advancing.size(); ++index) {
            const Item &before = items[advancing[index - 1]];
            const Item &after = items[advancing[index]];
            double edge = before.maxX <= after.minX
                ? (before.maxX + after.minX) / 2
                : std::clamp(after.atom.x, after.minX, before.maxX);
            edges.push_back(std::max(edges.back(), snap(edge)));
        }

        edges.push_back(std::max(edges.back(), std::ceil((std::max(right, items[advancing.back()].maxX) + margin) * scale) / scale));

        size_t first = atoms.size();

        for (size_t index = 0, slot = 0; index < items.size(); ++index) {
            GlyphAtom atom = items[index].atom;

            if (slot < advancing.size() && advancing[slot] == index) {
                atom.tile = {edges[slot], 0, edges[slot + 1] - edges[slot], 0};
                ++slot;
            } else {
                atom.tile = {atom.x, 0, 0, 0};
            }

            atoms.push_back(atom);
        }

        spans.push_back({first, atoms.size(), top - margin, bottom + margin, line.bottom()});
    }

    if (spans.empty()) {
        return atoms;
    }

    // Lines whose drawing overlaps split the overlap at the typographic
    // boundary between them, where neither usually has ink.
    std::vector<double> splits(spans.size() + 1);

    for (size_t index = 0; index <= spans.size(); ++index) {
        if (index == 0) {
            splits[index] = std::floor(spans.front().top * scale) / scale;
        } else if (index == spans.size()) {
            splits[index] = std::ceil(spans.back().bottom * scale) / scale;
        } else {
            const LineSpan &above = spans[index - 1];
            const LineSpan &below = spans[index];
            double split = above.bottom <= below.top
                ? (above.bottom + below.top) / 2
                : std::clamp(above.typographicBottom, below.top, above.bottom);
            splits[index] = std::max(splits[index - 1], snap(split));
        }
    }

    for (size_t index = 0; index < spans.size(); ++index) {
        for (size_t atom = spans[index].first; atom < spans[index].end; ++atom) {
            Rect &tile = atoms[atom].tile;

            tile.y = splits[index];

            if (tile.width > 0) {
                tile.height = splits[index + 1] - splits[index];
            }
        }
    }

    return atoms;
}

} // namespace atr
