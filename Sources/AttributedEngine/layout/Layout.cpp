// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#include "atr/layout/Layout.hpp"

#include "LayoutAnnotator.hpp"
#include "LineBreaker.hpp"
#include "Typesetter.hpp"

namespace atr {

namespace {

bool reusable(const Layout &previous, const Container &container) {
    const Container &old = previous.container;
    // Infinite widths compare equal; NaN never reaches here.
    return !previous.truncated && old.width == container.width && old.maxHeight == container.maxHeight
        && std::isinf(container.maxHeight) && old.maxLines == 0 && container.maxLines == 0
        && old.lineHeightMode == container.lineHeightMode && old.truncationToken == container.truncationToken;
}

// Paragraphs holding an attachment whose content size differs between the
// two containers.
std::vector<bool> changedParagraphs(const ResolvedDocument &resolved, const Container &old, const Container &now) {
    auto changed = [&](uint32_t attachment) {
        auto before = old.attachmentContentSizes.find(attachment);
        auto after = now.attachmentContentSizes.find(attachment);
        bool hadBefore = before != old.attachmentContentSizes.end();
        bool hasAfter = after != now.attachmentContentSizes.end();
        return hadBefore != hasAfter || (hadBefore && before->second != after->second);
    };
    std::vector<bool> result(resolved.paragraphs.size(), false);

    for (size_t index = 0; index < resolved.paragraphs.size(); ++index) {
        for (const Run &run : resolved.paragraphs[index].runs) {
            if (run.attachment && changed(*run.attachment)) {
                result[index] = true;
                break;
            }
        }
    }

    return result;
}

} // namespace

std::shared_ptr<const Layout> computeLayout(
    const Document &document,
    const ResolvedDocument &resolved,
    const FontTable &fonts,
    const Container &container,
    const Layout *previous
) {
    auto layout = std::make_shared<Layout>();
    layout->container = container;

    if (!(container.width > 0)) {
        return layout;
    }

    layout::LayoutContext context(document, resolved, fonts, container);
    layout::Typesetter typesetter(context);
    layout::LineBreaker breaker(context, typesetter, *layout);

    if (previous && reusable(*previous, container)) {
        breaker.reuse(*previous, changedParagraphs(resolved, previous->container, container));
    }

    breaker.run();
    layout::LayoutAnnotator(context, typesetter, *layout).run();
    return layout;
}

} // namespace atr
