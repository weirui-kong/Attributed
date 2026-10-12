// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#import "ATRDocument.h"

#include <memory>

#include "atr/document/Document.hpp"
#include "atr/layout/Layout.hpp"

@interface ATRDocument ()

- (nonnull instancetype)initWithDocument:(std::shared_ptr<const atr::Document>)document
                                   fonts:(nonnull NSArray<ATRPlatformFont *> *)fonts
                                  colors:(nonnull NSArray<ATRPlatformColor *> *)colors
                             defaultFont:(nonnull ATRPlatformFont *)defaultFont
    NS_DESIGNATED_INITIALIZER;

@property (nonatomic, readonly) const atr::Document &engineDocument;
@property (nonatomic, readonly) const atr::ResolvedDocument &resolvedDocument;
@property (nonatomic, readonly) const atr::FontTable &fontTable;

// `container` must describe the same limits as `engineContainer`, which may
// also carry attachment content-size overrides.
- (nonnull ATRTextLayout *)layoutWithEngineContainer:(const atr::Container &)engineContainer
                                           container:(ATRTextContainer)container;

@end
