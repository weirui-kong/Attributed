// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#pragma once

#include "LayoutContext.hpp"

namespace atr::layout {

struct AttachmentMetrics {
    double width = 0;
    double height = 0;
    // Bottom edge relative to the baseline, positive upward.
    double originY = 0;
};

struct ParagraphText {
    CFRef<CFMutableAttributedStringRef> string;
    CFRef<CTTypesetterRef> typesetter;
};

// Builds the CoreText input for each paragraph on first use: one attributed
// string per paragraph carrying fonts, kerning, writing direction, a run
// delegate per attachment, and the private style and attachment attributes.
class Typesetter {
public:
    explicit Typesetter(const LayoutContext &context);

    ParagraphText &paragraph(uint32_t index);
    CFRef<CFMutableDictionaryRef> attributes(uint32_t styleIndex) const;
    const AttachmentMetrics &attachmentMetrics(uint32_t attachment) const;

private:
    const LayoutContext &context_;
    std::vector<ParagraphText> paragraphs_;
    std::unordered_map<uint32_t, AttachmentMetrics> attachmentMetrics_;

    void addAttachment(
        CFMutableDictionaryRef attributes,
        uint32_t attachment,
        uint32_t styleIndex,
        std::optional<uint32_t> neighborStyle
    );
};

} // namespace atr::layout
