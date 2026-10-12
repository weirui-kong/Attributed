// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#pragma once

#include "atr/document/Document.hpp"

namespace atr::detail {

// Quotes UTF-16 text, escaping backslash, quote, and control characters.
// Unpaired surrogates become U+FFFD.
std::string quoted(const char16_t *characters, size_t length);
void appendField(std::string &fields, const std::string &field);
std::string describe(const Fill &fill);
std::string describe(const Underline &underline);
std::string describe(const Gesture &gesture);
const char *name(TextAlignment alignment);
const char *name(WritingDirection direction);
const char *name(GradientScope scope);

} // namespace atr::detail
