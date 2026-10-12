// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#import "ATRDocument.h"
#import "ATRTypes.h"

// Builds a document in engine memory. Structural misuse, such as nesting
// paragraphs or adding text outside a paragraph, raises
// NSInternalInconsistencyException.
@interface ATRDocumentBuilder : NSObject

// Registers the semantic label color as color 0 and the root foreground.
- (nonnull instancetype)init NS_DESIGNATED_INITIALIZER;

// Equal fonts, colors, and gradients share one index. `colors` and, when
// given, `locations` must each hold `count` elements; `count` must be
// positive.
- (int32_t)registerFont:(nonnull ATRPlatformFont *)font;
- (int32_t)registerColor:(nonnull ATRPlatformColor *)color;
- (int32_t)registerGradientWithColors:(const int32_t *_Nonnull)colors
                            locations:(const double *_Nullable)locations
                                count:(NSUInteger)count
                           descriptor:(ATRGradientDescriptor)descriptor;

// Returns the new interaction's ID, for use with pushSpan:interaction:.
- (uint32_t)registerInteractionWithGesture:(ATRGesture)gesture;

- (void)beginParagraph:(ATRParagraphStyle)paragraphStyle textStyle:(ATRTextStyle)textStyle;
- (void)endParagraph;
// Pass ATRNoInteraction for a span without an interaction.
- (void)pushSpan:(ATRTextStyle)textStyle interaction:(uint32_t)interaction;
- (void)popSpan;
- (void)appendText:(nonnull NSString *)text;
- (uint32_t)appendAttachment:(ATRAttachmentDescriptor)descriptor
          accessibilityLabel:(nullable NSString *)accessibilityLabel;

// The builder cannot be used after finishing. Text without a font uses the
// body text style on iOS and the system font size on macOS.
- (nonnull ATRDocument *)finish;

@end
