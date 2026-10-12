// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#include "atr/layout/Layout.hpp"

#include "LayoutAnnotator.hpp"
#include "LineBreaker.hpp"
#include "Typesetter.hpp"

namespace atr {

std::shared_ptr<const Layout> computeLayout(
    const Document &document,
    const ResolvedDocument &resolved,
    const FontTable &fonts,
    const Container &container
) {
    auto layout = std::make_shared<Layout>();

    if (!(container.width > 0)) {
        return layout;
    }

    layout::LayoutContext context(document, resolved, fonts, container);
    layout::Typesetter typesetter(context);
    layout::LineBreaker(context, typesetter, *layout).run();
    layout::LayoutAnnotator(context, typesetter, *layout).run();
    return layout;
}

} // namespace atr
