// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#pragma once

#include "atr/layout/Layout.hpp"

namespace atr::layout {

// Private attributes carried through CoreText so every CTRun, including
// truncation token runs, maps back to its resolved style and attachment.
inline const CFStringRef kStyleAttribute = CFSTR("ATRStyle");
inline const CFStringRef kAttachmentAttribute = CFSTR("ATRAttachment");
// Marks the runs of a truncation token, which map to no document text.
inline const CFStringRef kTruncationTokenAttribute = CFSTR("ATRTruncationToken");

// Wrapping is disabled by laying out against a width no line reaches.
constexpr double kUnboundedWidth = 1e9;
// Adjacent runs closer than this merge into one hit region or underline.
constexpr double kMergeTolerance = 0.5;

// The read-only inputs shared by every layout stage.
struct LayoutContext {
    const Document &document;
    const ResolvedDocument &resolved;
    const FontTable &fonts;
    const Container &container;
    bool finiteWidth;
    double breakWidth;

    LayoutContext(
        const Document &document,
        const ResolvedDocument &resolved,
        const FontTable &fonts,
        const Container &container
    )
        : document(document),
          resolved(resolved),
          fonts(fonts),
          container(container),
          finiteWidth(std::isfinite(container.width)),
          breakWidth(finiteWidth ? container.width : kUnboundedWidth) {}
};

inline CFRef<CFNumberRef> makeNumber(int32_t value) {
    return CFRef<CFNumberRef>::adopt(CFNumberCreate(nullptr, kCFNumberSInt32Type, &value));
}

inline CFRef<CFNumberRef> makeNumber(double value) {
    return CFRef<CFNumberRef>::adopt(CFNumberCreate(nullptr, kCFNumberDoubleType, &value));
}

inline std::optional<int32_t> intAttribute(CFDictionaryRef attributes, CFStringRef key) {
    auto number = static_cast<CFNumberRef>(CFDictionaryGetValue(attributes, key));

    if (!number) {
        return std::nullopt;
    }

    int32_t value = 0;
    CFNumberGetValue(number, kCFNumberSInt32Type, &value);
    return value;
}

} // namespace atr::layout
