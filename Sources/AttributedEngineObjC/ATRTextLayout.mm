// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#import "ATRTextLayout+Internal.h"

#import "ATRDocument+Internal.h"

#include <algorithm>

#include "atr/layout/Geometry.hpp"


#if !__has_feature(objc_arc)
#error "AttributedEngineObjC must be compiled with ARC."
#endif

namespace {

CGRect makeRect(const atr::Rect &rect) {
    return CGRectMake(rect.x, rect.y, rect.width, rect.height);
}

NSRange makeRange(atr::TextRange range) {
    return NSMakeRange(range.location, range.length);
}

uint32_t clampOffset(NSUInteger offset) {
    return static_cast<uint32_t>(std::min<NSUInteger>(offset, UINT32_MAX));
}

atr::TextRange clampRange(NSRange range) {
    uint32_t location = clampOffset(range.location);
    auto length = static_cast<uint32_t>(std::min<NSUInteger>(range.length, UINT32_MAX - location));
    return {location, length};
}

atr::TextPosition enginePosition(ATRTextPosition position) {
    return {
        clampOffset(position.offset),
        position.affinity == ATRTextAffinityUpstream ? atr::Affinity::Upstream : atr::Affinity::Downstream,
    };
}

} // namespace

@implementation ATRTextLayout {
    std::shared_ptr<const atr::Layout> _layout;
}

- (instancetype)initWithLayout:(std::shared_ptr<const atr::Layout>)layout
                      document:(ATRDocument *)document
                     container:(ATRTextContainer)container
               truncationToken:(NSString *)truncationToken
        attachmentContentSizes:(NSDictionary<NSNumber *, NSValue *> *)attachmentContentSizes {
    self = [super init];

    if (self) {
        _layout = std::move(layout);
        _document = document;
        _container = container;
        _truncationToken = [truncationToken copy];
        _attachmentContentSizes = [attachmentContentSizes copy] ?: @{};
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

- (atr::TextGeometry)geometry {
    return atr::TextGeometry(_document.resolvedDocument, *_layout);
}

- (NSUInteger)textLength {
    return self.geometry.textLength();
}

- (NSRange)visibleRange {
    return makeRange(self.geometry.visibleRange());
}

- (NSRange)rangeOfLineAtIndex:(NSUInteger)index {
    return makeRange(self.geometry.lineRange(index));
}

- (NSUInteger)lineIndexAtY:(CGFloat)y {
    return self.geometry.lineAtY(y).value_or(NSNotFound);
}

- (NSUInteger)lineIndexContainingPosition:(ATRTextPosition)position {
    return self.geometry.lineContaining(enginePosition(position)).value_or(NSNotFound);
}

- (NSRange)lineIndexesBetweenMinY:(CGFloat)minY maxY:(CGFloat)maxY {
    auto [first, end] = self.geometry.linesBetween(minY, maxY);
    return NSMakeRange(first, end - first);
}

- (NSUInteger)characterIndexAtPoint:(CGPoint)point {
    std::optional<uint32_t> index = self.geometry.characterIndex(point.x, point.y);
    return index ? *index : NSNotFound;
}

- (ATRTextPosition)closestPositionToPoint:(CGPoint)point {
    atr::TextPosition position = self.geometry.closestPosition(point.x, point.y);
    return {
        position.offset,
        position.affinity == atr::Affinity::Upstream ? ATRTextAffinityUpstream : ATRTextAffinityDownstream,
    };
}

- (CGRect)caretRectForPosition:(ATRTextPosition)position {
    return makeRect(self.geometry.caretRect(enginePosition(position)));
}

- (NSArray<NSValue *> *)selectionRectsForRange:(NSRange)range minY:(CGFloat)minY maxY:(CGFloat)maxY {
    NSMutableArray<NSValue *> *result = [NSMutableArray array];

    for (const atr::SelectionRect &selection : self.geometry.selectionRects(clampRange(range), minY, maxY)) {
        ATRSelectionRect value = {
            makeRect(selection.rect),
            selection.line,
            selection.rightToLeft,
            selection.containsStart,
            selection.containsEnd,
        };
        [result addObject:[NSValue valueWithBytes:&value objCType:@encode(ATRSelectionRect)]];
    }

    return result;
}

- (CGRect)boundingRectForRange:(NSRange)range {
    std::optional<atr::Rect> rect = self.geometry.boundingRect(clampRange(range));
    return rect ? makeRect(*rect) : CGRectNull;
}

- (NSRange)rangeEnclosingIndex:(NSUInteger)index granularity:(ATRTextGranularity)granularity {
    std::optional<atr::TextRange> range = self.geometry.rangeEnclosing(
        clampOffset(index),
        static_cast<atr::Granularity>(granularity)
    );
    return range ? makeRange(*range) : NSMakeRange(NSNotFound, 0);
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
