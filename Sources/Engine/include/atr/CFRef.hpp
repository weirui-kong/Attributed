// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#pragma once

#include <CoreFoundation/CoreFoundation.h>

#include <utility>

namespace atr {

// Owning reference to a Core Foundation object.
template <typename T> class CFRef {
public:
    CFRef() = default;

    // Adopts a +1 reference, as returned by Create and Copy functions.
    static CFRef adopt(T ref) {
        CFRef result;
        result.ref_ = ref;
        return result;
    }

    static CFRef retain(T ref) {
        if (ref) {
            CFRetain(ref);
        }

        return adopt(ref);
    }

    CFRef(const CFRef &other) : ref_(other.ref_) {
        if (ref_) {
            CFRetain(ref_);
        }
    }

    CFRef(CFRef &&other) noexcept : ref_(std::exchange(other.ref_, nullptr)) {}

    CFRef &operator=(CFRef other) noexcept {
        std::swap(ref_, other.ref_);
        return *this;
    }

    ~CFRef() {
        if (ref_) {
            CFRelease(ref_);
        }
    }

    T get() const { return ref_; }
    explicit operator bool() const { return ref_ != nullptr; }

private:
    T ref_ = nullptr;
};

} // namespace atr
