// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#import "ATRTextLayout+Internal.h"

#import "ATRDocument+Internal.h"

#include <algorithm>


#if !__has_feature(objc_arc)
#error "AttributedEngineObjC must be compiled with ARC."
#endif

namespace {

CGRect makeRect(const atr::Rect &rect) {
    return CGRectMake(rect.x, rect.y, rect.width, rect.height);
}

} // namespace

@implementation ATRTextLayout {
    std::shared_ptr<const atr::Layout> _layout;
}

- (instancetype)initWithLayout:(std::shared_ptr<const atr::Layout>)layout
                      document:(ATRDocument *)document
                     container:(ATRTextContainer)container {
    self = [super init];

    if (self) {
        _layout = std::move(layout);
        _document = document;
        _container = container;
    }

    return self;
}

- (const atr::Layout &)engineLayout {
    return *_layout;
}

- (CGSize)size {
    return CGSizeMake(_layout->width, _layout->height);
}

- (BOOL)isTruncated {
    return _layout->truncated;
}

- (NSUInteger)lineCount {
    return _layout->lines.size();
}

- (NSUInteger)attachmentFrameCount {
    return _layout->attachments.size();
}

- (NSUInteger)gradientGroupCount {
    return _layout->gradientGroups.size();
}

- (NSUInteger)decorationCount {
    return _layout->decorations.size();
}

- (ATRLineInfo)lineAtIndex:(NSUInteger)index {
    const atr::Line &line = _layout->lines.at(index);
    ATRLineInfo info = {};
    info.paragraph = line.paragraph;
    info.location = line.location;
    info.length = line.length;
    info.frame = CGRectMake(line.x, line.top, line.width, line.bottom() - line.top);
    info.baseline = line.baseline;
    info.drawnTop = line.drawnTop();
    info.drawnBottom = line.drawnBottom();
    info.truncated = line.truncated;
    return info;
}

- (ATRAttachmentFrame)attachmentFrameAtIndex:(NSUInteger)index {
    const atr::AttachmentFrame &frame = _layout->attachments.at(index);
    return {frame.attachment, frame.line, makeRect(frame.frame)};
}

- (ATRGradientGroupInfo)gradientGroupAtIndex:(NSUInteger)index {
    const atr::GradientGroup &group = _layout->gradientGroups.at(index);
    return {
        group.gradient,
        static_cast<ATRGradientScope>(group.scope),
        group.scopeInstance,
        makeRect(group.rect),
        group.memberCount,
    };
}

- (NSUInteger)hitRegionCount {
    return _layout->hitRegions.size();
}

- (ATRHitRegion)hitRegionAtIndex:(NSUInteger)index {
    const atr::HitRegion &region = _layout->hitRegions.at(index);
    return {region.interactionSet, region.line, makeRect(region.rect)};
}

- (NSArray<NSNumber *> *)interactionsInSet:(uint32_t)interactionSet {
    NSMutableArray<NSNumber *> *result = [NSMutableArray array];

    for (uint32_t interaction : _document.resolvedDocument.interactionSets.at(interactionSet)) {
        [result addObject:@(interaction)];
    }

    return result;
}

- (NSArray<NSValue *> *)rectsForInteraction:(uint32_t)interaction {
    const auto &sets = _document.resolvedDocument.interactionSets;
    NSMutableArray<NSValue *> *result = [NSMutableArray array];

    for (const atr::HitRegion &region : _layout->hitRegions) {
        const auto &set = sets.at(region.interactionSet);

        if (std::find(set.begin(), set.end(), interaction) != set.end()) {
            CGRect rect = makeRect(region.rect);
            [result addObject:[NSValue valueWithBytes:&rect objCType:@encode(CGRect)]];
        }
    }

    return result;
}

- (ATRDecorationInfo)decorationAtIndex:(NSUInteger)index {
    const atr::DecorationSegment &segment = _layout->decorations.at(index);
    ATRDecorationInfo info = {};
    info.line = segment.line;
    info.rect = CGRectMake(
        segment.minX,
        segment.centerY - segment.thickness / 2,
        segment.maxX - segment.minX,
        segment.thickness
    );
    info.gradientGroup = segment.group ? static_cast<int32_t>(*segment.group) : -1;
    return info;
}

@end
