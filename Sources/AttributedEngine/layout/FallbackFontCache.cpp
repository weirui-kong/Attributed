// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#include "atr/layout/Layout.hpp"

namespace atr {

CTFontRef FallbackFontCache::fallback(int32_t font, CTFontRef base, CFStringRef string, CFRange range) {
    // Created outside the lock; only the lookup is serialized.
    auto created = CFRef<CTFontRef>::adopt(CTFontCreateForString(base, string, range));
    auto name = CFRef<CFStringRef>::adopt(CTFontCopyPostScriptName(created.get()));
    std::lock_guard<std::mutex> lock(mutex_);

    for (const Entry &entry : entries_) {
        if (entry.font == font && CFEqual(entry.name.get(), name.get())) {
            return entry.fallback.get();
        }
    }

    entries_.push_back({font, name, created});
    return entries_.back().fallback.get();
}

} // namespace atr
