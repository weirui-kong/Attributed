// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#pragma once

#include "atr/document/Document.hpp"

namespace atr {

// The default font is supplied by the facade, outside the font table.
constexpr int32_t kDefaultFont = -1;

constexpr uint32_t kNoInteractionSet = UINT32_MAX;

// U+FFFC stands in for an attachment in paragraph text.
constexpr char16_t kAttachmentCharacter = u'\uFFFC';

// A text style with inheritance applied and every field concrete.
struct ResolvedTextStyle {
    int32_t font = kDefaultFont;
    Fill foreground;
    std::optional<int32_t> backgroundColor;
    double kern = 0;
    double baselineOffset = 0;
    std::optional<Underline> underline;
    // Set whenever `underline` is: the explicit fill, else the foreground.
    std::optional<Fill> underlineFill;
    // Index into ResolvedDocument::interactionSets.
    uint32_t interactionSet = kNoInteractionSet;

    bool operator==(const ResolvedTextStyle &other) const;
};

struct ResolvedParagraphStyle {
    TextAlignment alignment = TextAlignment::Natural;
    // Never Natural after resolution: natural paragraphs take the direction
    // of their first strong character, defaulting to left-to-right.
    WritingDirection direction = WritingDirection::LeftToRight;
    double lineSpacing = 0;
    double paragraphSpacing = 0;
};

// A maximal range of paragraph text with one resolved style. Attachments
// are always their own one-character run.
struct Run {
    uint32_t location = 0;
    uint32_t length = 0;
    uint32_t style = 0;
    std::optional<uint32_t> attachment;
};

struct ResolvedParagraph {
    ResolvedParagraphStyle style;
    // Style of the paragraph scope itself; sizes an empty paragraph.
    uint32_t paragraphTextStyle = 0;
    // Where the paragraph starts in the document text.
    uint32_t start = 0;
    std::u16string text;
    std::vector<Run> runs;
};

struct ResolvedDocument {
    std::vector<ResolvedTextStyle> styles;
    // Interaction IDs that apply to a run, innermost first, at most one per
    // gesture key. Equal sets share one index.
    std::vector<std::vector<uint32_t>> interactionSets;
    // Indexed by interaction ID: the UTF-16 location and length of the
    // interaction's span in the document text, where paragraphs are joined
    // by one newline and each attachment is one U+FFFC.
    std::vector<std::pair<uint32_t, uint32_t>> interactionRanges;

    // Length of the document text in the same index space.
    uint32_t length() const;
    // Document text for a range in the same index space.
    std::u16string text(uint32_t location, uint32_t length) const;
    std::vector<ResolvedParagraph> paragraphs;

    // Stable text form for tests.
    std::string dump() const;
};

ResolvedDocument resolve(const Document &document);

} // namespace atr
