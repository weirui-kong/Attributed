// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#import "ATRTextLayout.h"
#import "ATRTypes.h"

// Immutable document produced by ATRDocumentBuilder. Resource tables keep
// platform fonts and colors unresolved so dynamic colors can be re-resolved
// per appearance.
@interface ATRDocument : NSObject

@property (nonatomic, readonly) NSUInteger fontCount;
@property (nonatomic, readonly) NSUInteger colorCount;
@property (nonatomic, readonly) NSUInteger gradientCount;
@property (nonatomic, readonly) NSUInteger attachmentCount;

- (nonnull instancetype)init NS_UNAVAILABLE;
+ (nonnull instancetype)new NS_UNAVAILABLE;

- (nonnull ATRPlatformFont *)fontAtIndex:(NSUInteger)index;
- (nonnull ATRPlatformColor *)colorAtIndex:(NSUInteger)index;

@property (nonatomic, readonly) NSUInteger interactionCount;
- (ATRGesture)gestureForInteraction:(uint32_t)interaction;
// The interaction's span in the document text, where paragraphs are joined
// by one newline and each attachment is one U+FFFC (UTF-16 units).
- (NSRange)rangeForInteraction:(uint32_t)interaction;
- (nonnull NSString *)textInRange:(NSRange)range;

// Thread-safe. A nil token uses U+2026.
- (nonnull ATRTextLayout *)layoutWithContainer:(ATRTextContainer)container
                               truncationToken:(nullable NSString *)truncationToken;

// Like layoutWithContainer:truncationToken:, with content sizes that became
// known after the document was built (loaded AsyncImages), keyed by
// attachment ID with CGSize values.
- (nonnull ATRTextLayout *)layoutWithContainer:(ATRTextContainer)container
                               truncationToken:(nullable NSString *)truncationToken
                        attachmentContentSizes:(nullable NSDictionary<NSNumber *, NSValue *> *)attachmentContentSizes;

// Like the above, reusing the lines of `previousLayout`, a layout of this
// document, for paragraphs whose attachment content sizes did not change.
// Applies only without line or height limits and when the other inputs are
// equal; otherwise it lays out everything. Ignored for another document.
- (nonnull ATRTextLayout *)layoutWithContainer:(ATRTextContainer)container
                               truncationToken:(nullable NSString *)truncationToken
                        attachmentContentSizes:(nullable NSDictionary<NSNumber *, NSValue *> *)attachmentContentSizes
                                previousLayout:(nullable ATRTextLayout *)previousLayout;

- (ATRAttachmentDescriptor)attachmentDescriptorAtIndex:(NSUInteger)index;

// Paragraphs joined by newlines, with attachments replaced by their
// accessibility labels; for accessibility.
@property (nonatomic, readonly, nonnull) NSString *plainText;

// Inheritance-resolved paragraphs and runs, for tests.
- (nonnull NSString *)resolvedDump;

// Ops and gradients first; font and color descriptions follow a "---" line
// because platform descriptions vary across OS versions.
- (nonnull NSString *)dump;

@end
