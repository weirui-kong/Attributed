// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#import "ATRTypes.h"

@class ATRDocument;

// Immutable layout of a document for one container. Safe to create and read
// on any thread.
@interface ATRTextLayout : NSObject

@property (nonatomic, readonly, nonnull) ATRDocument *document;
@property (nonatomic, readonly) ATRTextContainer container;
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

@end
