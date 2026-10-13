// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#pragma once

#include <CoreText/CoreText.h>

#include <algorithm>
#include <cmath>
#include <limits>
#include <memory>
#include <mutex>
#include <unordered_map>
#include <utility>
#include <vector>

#include "atr/support/CFRef.hpp"
#include "atr/resolve/Resolve.hpp"

namespace atr {

// CoreText makes its own fallback font objects for every typesetter, and
// layout uses one typesetter per paragraph, so a document with many
// paragraphs in fallback scripts would hold thousands of copies of the same
// few fonts, tens of kilobytes each. Layout assigns fallback fonts from this
// cache instead, so each fallback of a font exists once per document.
// Thread-safe.
class FallbackFontCache {
public:
    // The fallback CoreText picks for the start of `range`, as the shared
    // instance for `font`, the index of `base` in its font table.
    CTFontRef fallback(int32_t font, CTFontRef base, CFStringRef string, CFRange range);

private:
    struct Entry {
        int32_t font;
        CFRef<CFStringRef> name;
        CFRef<CTFontRef> fallback;
    };

    std::mutex mutex_;
    std::vector<Entry> entries_;
};

// Fonts as CoreText objects, so layout never touches UIKit or AppKit.
struct FontTable {
    CFRef<CTFontRef> defaultFont;
    std::vector<CFRef<CTFontRef>> fonts;
    std::shared_ptr<FallbackFontCache> fallbacks = std::make_shared<FallbackFontCache>();

    CTFontRef font(int32_t index) const {
        return index == kDefaultFont ? defaultFont.get() : fonts[index].get();
    }
};

// How glyphs that extend past the font's ascent or descent, such as stacked
// marks in Thai or Myanmar, affect line height.
enum class LineHeightMode : uint8_t {
    // Lines use the fonts' typographic metrics; tall glyphs may overlap
    // neighboring lines, as in UIKit text views.
    Typographic,
    // Lines grow to contain every glyph's actual bounds.
    GlyphBounds,
};

struct Container {
    // Must be positive. An infinite width disables wrapping and alignment.
    double width = std::numeric_limits<double>::infinity();
    double maxHeight = std::numeric_limits<double>::infinity();
    // Zero means unlimited.
    uint32_t maxLines = 0;
    // Styled like the character it follows.
    std::u16string truncationToken = u"\u2026";
    LineHeightMode lineHeightMode = LineHeightMode::Typographic;
    // Content sizes that became known after the document was built, keyed
    // by attachment ID; used by AsyncImage attachments once loaded.
    std::unordered_map<uint32_t, std::pair<double, double>> attachmentContentSizes;
};

// Geometry uses a top-left origin with y growing downward.
struct Rect {
    double x = 0;
    double y = 0;
    double width = 0;
    double height = 0;
};

struct LineRun {
    CFRef<CTRunRef> run;
    uint32_t style = 0;
    std::optional<uint32_t> attachment;
    // Horizontal extent in layout coordinates.
    double x = 0;
    double width = 0;
    // Runs from color fonts, such as emoji, skip gradient fills by default.
    bool colorGlyphs = false;
    // A truncation token run; its string indices are not document text.
    bool truncationToken = false;
    std::optional<uint32_t> fillGroup;
};

struct Line {
    // Null for an empty paragraph.
    CFRef<CTLineRef> line;
    uint32_t paragraph = 0;
    // Paragraph-local UTF-16 range of the text the line shows. A truncated
    // line covers only its text before the token.
    uint32_t location = 0;
    uint32_t length = 0;
    double x = 0;
    double top = 0;
    double baseline = 0;
    double ascent = 0;
    double descent = 0;
    double leading = 0;
    // Actual glyph extent above and below the baseline, measured glyph by
    // glyph in every mode. Drawing and tiling use it so tall glyphs are
    // never clipped.
    double inkAscent = 0;
    double inkDescent = 0;
    double width = 0;
    bool truncated = false;
    std::vector<LineRun> runs;

    double bottom() const { return baseline + descent + leading; }
    double drawnTop() const { return baseline - std::max(ascent, inkAscent); }
    double drawnBottom() const { return baseline + std::max(descent, inkDescent); }
};

struct AttachmentFrame {
    uint32_t attachment = 0;
    uint32_t line = 0;
    Rect frame;
};

// Runs whose fills use an equal gradient within one scope instance are drawn
// as one gradient over `rect`, the union of their typographic bounds.
struct GradientGroup {
    int32_t gradient = 0;
    GradientScope scope = GradientScope::Paragraph;
    // Line index, paragraph index, or zero, depending on `scope`.
    uint32_t scopeInstance = 0;
    Rect rect;
    uint32_t memberCount = 0;
};

// One drawn underline segment: adjacent runs with an equal underline, fill,
// and resolved metrics are merged before corners are applied.
struct DecorationSegment {
    uint32_t line = 0;
    double minX = 0;
    double maxX = 0;
    double centerY = 0;
    double thickness = 0;
    Underline underline;
    Fill fill;
    std::optional<uint32_t> group;
};

// Where an interaction set can be hit: adjacent runs on one line with the
// same set, spanning the line's typographic height.
struct HitRegion {
    uint32_t interactionSet = 0;
    uint32_t line = 0;
    Rect rect;
};

class Layout {
public:
    // The container this layout was made for.
    Container container;
    double width = 0;
    double height = 0;
    bool truncated = false;
    std::vector<Line> lines;
    std::vector<AttachmentFrame> attachments;
    std::vector<GradientGroup> gradientGroups;
    std::vector<DecorationSegment> decorations;
    std::vector<HitRegion> hitRegions;
};

// Safe to call on any thread: it uses only CoreText and immutable inputs.
//
// `previous`, a layout of the same document, lets a relayout that only
// changes attachment content sizes, such as an AsyncImage arriving, break
// just the paragraphs holding those attachments and shift the others' lines.
// It is used only when it was made for the same container apart from content
// sizes, without line or height limits, and was not truncated; otherwise
// everything is laid out again.
std::shared_ptr<const Layout> computeLayout(
    const Document &document,
    const ResolvedDocument &resolved,
    const FontTable &fonts,
    const Container &container,
    const Layout *previous = nullptr
);

} // namespace atr
