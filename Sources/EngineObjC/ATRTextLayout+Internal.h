// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#import "ATRTextLayout.h"

#include <memory>

#include "atr/Layout.hpp"

@interface ATRTextLayout ()

- (nonnull instancetype)initWithLayout:(std::shared_ptr<const atr::Layout>)layout
                              document:(nonnull ATRDocument *)document
                             container:(ATRTextContainer)container NS_DESIGNATED_INITIALIZER;

@property (nonatomic, readonly) const atr::Layout &engineLayout;

@end
