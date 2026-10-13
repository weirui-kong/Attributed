// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#import "ATRTypes.h"

@class ATRDocument;

// Immutable layout of a document for one container. Safe to create and read
// on any thread.
@interface ATRTextLayout : NSObject

@property (nonatomic, readonly, nonnull) ATRDocument *document;
@property (nonatomic, readonly) ATRTextContainer container;
// The inputs besides the container, so a view can tell whether a layout made
// elsewhere still matches its own settings.
@property (nonatomic, readonly, copy, nullable) NSString *truncationToken;
@property (nonatomic, readonly, copy, nonnull) NSDictionary<NSNumber *, NSValue *> *attachmentContentSizes;
// Used width and total height, unrounded.
@property (nonatomic, readonly) CGSize size;
@property (nonatomic, readonly, getter=isTruncated) BOOL truncated;
@property (nonatomic, readonly) NSUInteger lineCount;
@property (nonatomic, readonly) NSUInteger attachmentFrameCount;
@property (nonatomic, readonly) NSUInteger gradientGroupCount;
@property (nonatomic, readonly) NSUInteger decorationCount;

- (nonnull instancetype)init NS_UNAVAILABLE;
+ (nonnull instancetype)new NS_UNAVAILABLE;

- (ATRLineInfo)lineAtIndex:(NSUInteger)index;
- (ATRAttachmentFrame)attachmentFrameAtIndex:(NSUInteger)index;
- (ATRGradientGroupInfo)gradientGroupAtIndex:(NSUInteger)index;
- (ATRDecorationInfo)decorationAtIndex:(NSUInteger)index;

@property (nonatomic, readonly) NSUInteger hitRegionCount;
- (ATRHitRegion)hitRegionAtIndex:(NSUInteger)index;
// Interaction IDs of a set, innermost first.
- (nonnull NSArray<NSNumber *> *)interactionsInSet:(uint32_t)interactionSet;
// Every hit rect whose set includes `interaction`, as CGRect values.
- (nonnull NSArray<NSValue *> *)rectsForInteraction:(uint32_t)interaction;

// Position and rect queries. Offsets are document-global UTF-16 units, where
// paragraphs are joined by one newline and each attachment is one U+FFFC.
// Missing results are NSNotFound, {NSNotFound, 0}, or CGRectNull.
@property (nonatomic, readonly) NSUInteger textLength;
// The drawn text; excludes text cut by truncation or container limits.
@property (nonatomic, readonly) NSRange visibleRange;
- (NSRange)rangeOfLineAtIndex:(NSUInteger)index;
// NSNotFound in the gap between lines.
- (NSUInteger)lineIndexAtY:(CGFloat)y;
// NSNotFound past the visible text.
- (NSUInteger)lineIndexContainingPosition:(ATRTextPosition)position;
// Lines whose frames overlap [minY, maxY).
- (NSRange)lineIndexesBetweenMinY:(CGFloat)minY maxY:(CGFloat)maxY;
// NSNotFound off glyphs, in line gaps, and on a truncation token.
- (NSUInteger)characterIndexAtPoint:(CGPoint)point;
- (ATRTextPosition)closestPositionToPoint:(CGPoint)point;
- (CGRect)caretRectForPosition:(ATRTextPosition)position;
// ATRSelectionRect values for lines overlapping [minY, maxY).
- (nonnull NSArray<NSValue *> *)selectionRectsForRange:(NSRange)range minY:(CGFloat)minY maxY:(CGFloat)maxY;
- (CGRect)boundingRectForRange:(NSRange)range;
- (NSRange)rangeEnclosingIndex:(NSUInteger)index granularity:(ATRTextGranularity)granularity;

@end
