// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#import <Foundation/Foundation.h>
#import <TargetConditionals.h>

#if TARGET_OS_OSX
#import <AppKit/AppKit.h>
typedef NSFont ATRPlatformFont;
typedef NSColor ATRPlatformColor;
typedef NSImage ATRPlatformImage;
typedef NSView ATRPlatformView;
typedef NSAppearance ATRPlatformAppearance;
typedef NSGestureRecognizer ATRPlatformGestureRecognizer;
#else
#import <UIKit/UIKit.h>
typedef UIFont ATRPlatformFont;
typedef UIColor ATRPlatformColor;
typedef UIImage ATRPlatformImage;
typedef UIView ATRPlatformView;
typedef UITraitCollection ATRPlatformAppearance;
typedef UIGestureRecognizer ATRPlatformGestureRecognizer;
#endif

// Plain C value types crossing from Swift into the engine. Each struct uses
// a field mask: a cleared bit means the field inherits from the enclosing
// scope and its value is ignored.

typedef NS_ENUM(uint8_t, ATRTextAlignment) {
    ATRTextAlignmentNatural,
    ATRTextAlignmentLeft,
    ATRTextAlignmentCenter,
    ATRTextAlignmentRight,
    ATRTextAlignmentJustified,
};

typedef NS_ENUM(uint8_t, ATRWritingDirection) {
    ATRWritingDirectionNatural,
    ATRWritingDirectionLeftToRight,
    ATRWritingDirectionRightToLeft,
};

typedef NS_ENUM(uint8_t, ATRGradientScope) {
    ATRGradientScopeLine,
    ATRGradientScopeParagraph,
    ATRGradientScopeDocument,
};

typedef NS_ENUM(uint8_t, ATRImagePipeline) {
    ATRImagePipelineImage,
    ATRImagePipelineAsyncImage,
};

typedef NS_ENUM(uint8_t, ATRAttachmentSizeKind) {
    ATRAttachmentSizeKindFixed,
    ATRAttachmentSizeKindAdaptive,
};

typedef NS_ENUM(uint8_t, ATRAttachmentAlignmentKind) {
    ATRAttachmentAlignmentKindBaseline,
    ATRAttachmentAlignmentKindCenter,
    ATRAttachmentAlignmentKindTop,
    ATRAttachmentAlignmentKindBottom,
    ATRAttachmentAlignmentKindOffset,
};

typedef NS_ENUM(uint8_t, ATRFillKind) {
    ATRFillKindColor,
    ATRFillKindGradient,
};

// A color index or a gradient index, depending on `kind`.
typedef struct ATRFill {
    ATRFillKind kind;
    int32_t index;
} ATRFill;

typedef NS_ENUM(uint8_t, ATRUnderlineLines) {
    ATRUnderlineLinesSingle,
    ATRUnderlineLinesDouble,
};

typedef NS_ENUM(uint8_t, ATRUnderlinePattern) {
    ATRUnderlinePatternSolid,
    ATRUnderlinePatternDot,
    ATRUnderlinePatternDash,
    ATRUnderlinePatternDashDot,
    ATRUnderlinePatternDashDotDot,
};

typedef NS_ENUM(uint8_t, ATRUnderlineCorners) {
    ATRUnderlineCornersSquare,
    // Uses `cornerRadius`, clamped to half the drawn thickness.
    ATRUnderlineCornersRadius,
    // Half the drawn thickness.
    ATRUnderlineCornersCapsule,
};

// Underlines are engine-drawn decorations. A thickness of zero or less means
// the font's underline thickness.
typedef struct ATRUnderline {
    ATRUnderlineLines lines;
    ATRUnderlinePattern pattern;
    double thickness;
    ATRUnderlineCorners corners;
    double cornerRadius;
} ATRUnderline;

typedef NS_OPTIONS(uint32_t, ATRTextStyleFields) {
    ATRTextStyleFieldFont = 1 << 0,
    ATRTextStyleFieldForeground = 1 << 1,
    ATRTextStyleFieldBackgroundColor = 1 << 2,
    ATRTextStyleFieldKern = 1 << 3,
    ATRTextStyleFieldBaselineOffset = 1 << 4,
    ATRTextStyleFieldUnderline = 1 << 5,
    ATRTextStyleFieldUnderlineFill = 1 << 6,
};

typedef struct ATRTextStyle {
    ATRTextStyleFields fields;
    int32_t font;
    ATRFill foreground;
    int32_t backgroundColor;
    double kern;
    double baselineOffset;
    ATRUnderline underline;
    ATRFill underlineFill;
} ATRTextStyle;

typedef NS_OPTIONS(uint32_t, ATRParagraphStyleFields) {
    ATRParagraphStyleFieldAlignment = 1 << 0,
    ATRParagraphStyleFieldWritingDirection = 1 << 1,
    ATRParagraphStyleFieldLineSpacing = 1 << 2,
    ATRParagraphStyleFieldParagraphSpacing = 1 << 3,
};

typedef struct ATRParagraphStyle {
    ATRParagraphStyleFields fields;
    ATRTextAlignment alignment;
    ATRWritingDirection writingDirection;
    double lineSpacing;
    double paragraphSpacing;
} ATRParagraphStyle;

typedef NS_OPTIONS(uint32_t, ATRAttachmentFields) {
    ATRAttachmentFieldMaxWidth = 1 << 0,
    ATRAttachmentFieldMaxHeight = 1 << 1,
    ATRAttachmentFieldContentSize = 1 << 2,
};

typedef struct ATRAttachmentDescriptor {
    ATRAttachmentFields fields;
    ATRAttachmentSizeKind sizeKind;
    // Fixed size.
    double width;
    double height;
    // Adaptive maxima.
    double maxWidth;
    double maxHeight;
    ATRAttachmentAlignmentKind alignmentKind;
    double alignmentOffset;
    ATRImagePipeline pipeline;
    double contentWidth;
    double contentHeight;
} ATRAttachmentDescriptor;

typedef struct ATRGradientDescriptor {
    double startX;
    double startY;
    double endX;
    double endY;
    ATRGradientScope scope;
} ATRGradientDescriptor;

extern const uint32_t ATRNoInteraction;

typedef NS_ENUM(uint8_t, ATRGestureKind) {
    ATRGestureKindTap,
    ATRGestureKindLongPress,
};

// Platform-neutral gesture description; recognizers are made from it by the
// view layer.
typedef struct ATRGesture {
    ATRGestureKind kind;
    // Taps only; at least one.
    uint32_t tapCount;
    // Long presses only, in seconds.
    double minimumPressDuration;
} ATRGesture;

typedef NS_ENUM(uint8_t, ATRLineHeightMode) {
    // Typographic font metrics; tall glyphs may overlap neighboring lines.
    ATRLineHeightModeTypographic,
    // Lines grow to contain every glyph's actual bounds, for example stacked
    // marks in Thai or Myanmar.
    ATRLineHeightModeGlyphBounds,
};

typedef struct ATRTextContainer {
    // Must be positive. INFINITY disables wrapping and alignment.
    double width;
    // INFINITY for no limit.
    double maxHeight;
    // Zero for no limit.
    uint32_t maximumNumberOfLines;
    ATRLineHeightMode lineHeightMode;
} ATRTextContainer;

// Geometry uses a top-left origin with y growing downward.
typedef struct ATRLineInfo {
    uint32_t paragraph;
    // Paragraph-local UTF-16 range.
    uint32_t location;
    uint32_t length;
    // Typographic frame: origin x, line top, used width, and line height.
    CGRect frame;
    CGFloat baseline;
    // Vertical extent including glyphs that overflow the typographic frame.
    CGFloat drawnTop;
    CGFloat drawnBottom;
    BOOL truncated;
} ATRLineInfo;

typedef struct ATRAttachmentFrame {
    uint32_t attachment;
    uint32_t line;
    CGRect frame;
} ATRAttachmentFrame;

typedef struct ATRGradientGroupInfo {
    int32_t gradient;
    ATRGradientScope scope;
    uint32_t scopeInstance;
    CGRect rect;
    uint32_t memberCount;
} ATRGradientGroupInfo;

typedef struct ATRDecorationInfo {
    uint32_t line;
    // Spans the merged segment; vertically centered on the underline.
    CGRect rect;
    // -1 when the fill is not a gradient.
    int32_t gradientGroup;
} ATRDecorationInfo;

// Where an interaction set can be hit: the union of its runs on one line.
typedef struct ATRHitRegion {
    uint32_t interactionSet;
    uint32_t line;
    CGRect rect;
} ATRHitRegion;
