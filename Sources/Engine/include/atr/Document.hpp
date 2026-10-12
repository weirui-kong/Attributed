// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#pragma once

#include <cstddef>
#include <cstdint>
#include <map>
#include <memory>
#include <optional>
#include <string>
#include <vector>

namespace atr {

enum class TextAlignment : uint8_t { Natural, Left, Center, Right, Justified };
enum class WritingDirection : uint8_t { Natural, LeftToRight, RightToLeft };
enum class GradientScope : uint8_t { Line, Paragraph, Document };
enum class ImagePipeline : uint8_t { Image, AsyncImage };
enum class AttachmentSizeKind : uint8_t { Fixed, Adaptive };
enum class AttachmentAlignmentKind : uint8_t { Baseline, Center, Top, Bottom, Offset };

enum class FillKind : uint8_t { Color, Gradient };

// `index` refers to the facade's color table or to the document's gradients.
struct Fill {
    FillKind kind = FillKind::Color;
    int32_t index = 0;

    bool operator==(const Fill &other) const = default;
};

enum class UnderlineLines : uint8_t { Single, Double };
enum class UnderlinePattern : uint8_t { Solid, Dot, Dash, DashDot, DashDotDot };

enum class UnderlineCorners : uint8_t { Square, Radius, Capsule };

// Drawn by the engine as a decoration. An empty thickness uses the font's
// underline thickness. Corners apply to both ends of every drawn segment,
// including each dash and dot; a radius is clamped to half the drawn
// thickness. Adjacent runs on one line with an equal underline and fill are
// merged into one segment before corners are applied.
struct Underline {
    UnderlineLines lines = UnderlineLines::Single;
    UnderlinePattern pattern = UnderlinePattern::Solid;
    std::optional<double> thickness;
    UnderlineCorners corners = UnderlineCorners::Square;
    double cornerRadius = 0;

    bool operator==(const Underline &other) const = default;
};

// Resource fields are indices into the facade's resource tables. An empty
// optional inherits the value from the enclosing scope. An underline without
// a fill after inheritance uses the foreground fill.
struct TextStyle {
    std::optional<int32_t> font;
    std::optional<Fill> foreground;
    std::optional<int32_t> backgroundColor;
    std::optional<double> kern;
    std::optional<double> baselineOffset;
    std::optional<Underline> underline;
    std::optional<Fill> underlineFill;
};

struct ParagraphStyle {
    std::optional<TextAlignment> alignment;
    std::optional<WritingDirection> writingDirection;
    std::optional<double> lineSpacing;
    std::optional<double> paragraphSpacing;
};

struct Gradient {
    std::vector<int32_t> colors;
    std::optional<std::vector<double>> locations;
    double startX = 0;
    double startY = 0;
    double endX = 0;
    double endY = 0;
    GradientScope scope = GradientScope::Paragraph;

    bool operator<(const Gradient &other) const;
};

struct AttachmentDescriptor {
    AttachmentSizeKind sizeKind = AttachmentSizeKind::Fixed;
    double width = 0;
    double height = 0;
    std::optional<double> maxWidth;
    std::optional<double> maxHeight;
    AttachmentAlignmentKind alignmentKind = AttachmentAlignmentKind::Baseline;
    double alignmentOffset = 0;
    ImagePipeline pipeline = ImagePipeline::Image;
    // Known when the document is built only for the image pipeline.
    std::optional<double> contentWidth;
    std::optional<double> contentHeight;
    std::optional<std::u16string> accessibilityLabel;
};

enum class GestureKind : uint8_t { Tap, LongPress };

struct Gesture {
    GestureKind kind = GestureKind::Tap;
    // Taps only; at least one.
    uint32_t tapCount = 1;
    // Long presses only, in seconds.
    double minimumPressDuration = 0.5;

    // Gestures with an equal key compete; nested interactions keep only the
    // innermost one per key. Taps with different counts coexist.
    std::pair<GestureKind, uint32_t> key() const {
        return {kind, kind == GestureKind::Tap ? tapCount : 0};
    }
};

enum class OpKind : uint8_t { BeginParagraph, EndParagraph, PushSpan, PopSpan, Text, Attachment };

// Operand meaning by kind:
//   BeginParagraph: paragraph style index, text style index
//   PushSpan:       text style index, interaction id or kNoInteraction
//   Text:           UTF-16 offset and length in the text pool
//   Attachment:     attachment id
struct Op {
    OpKind kind;
    uint32_t first;
    uint32_t second;
};

constexpr uint32_t kNoInteraction = UINT32_MAX;

class Document {
public:
    const TextStyle &baseTextStyle() const { return baseTextStyle_; }
    const ParagraphStyle &baseParagraphStyle() const { return baseParagraphStyle_; }
    const std::vector<Op> &ops() const { return ops_; }
    const std::u16string &text() const { return text_; }
    const std::vector<TextStyle> &textStyles() const { return textStyles_; }
    const std::vector<ParagraphStyle> &paragraphStyles() const { return paragraphStyles_; }
    const std::vector<Gradient> &gradients() const { return gradients_; }
    // Indexed by interaction ID.
    const std::vector<Gesture> &interactions() const { return interactions_; }
    const std::vector<AttachmentDescriptor> &attachments() const { return attachments_; }

    // Stable text form of the ops and gradients, used by snapshot tests.
    std::string dump() const;

private:
    friend class DocumentBuilder;

    TextStyle baseTextStyle_;
    ParagraphStyle baseParagraphStyle_;
    std::vector<Op> ops_;
    std::u16string text_;
    std::vector<TextStyle> textStyles_;
    std::vector<ParagraphStyle> paragraphStyles_;
    std::vector<Gradient> gradients_;
    std::vector<Gesture> interactions_;
    std::vector<AttachmentDescriptor> attachments_;
};

enum class BuildStatus : uint8_t {
    Ok,
    NestedParagraph,
    ContentOutsideParagraph,
    MismatchedScope,
    UnknownInteraction,
    UnclosedScope,
    AlreadyFinished,
};

const char *describe(BuildStatus status);

// Enforces the document invariants: scopes nest strictly, paragraphs never
// nest, text and attachments only appear inside a paragraph, and a span
// either lies within one paragraph or encloses whole paragraphs.
class DocumentBuilder {
public:
    DocumentBuilder();

    void setBaseTextStyle(const TextStyle &style);
    BuildStatus beginParagraph(const ParagraphStyle &paragraphStyle, const TextStyle &textStyle);
    BuildStatus endParagraph();
    BuildStatus pushSpan(const TextStyle &textStyle, uint32_t interaction);
    BuildStatus popSpan();
    BuildStatus appendText(const char16_t *characters, size_t length);
    BuildStatus appendAttachment(const AttachmentDescriptor &descriptor, uint32_t &outID);
    int32_t registerGradient(const Gradient &gradient);
    uint32_t registerInteraction(const Gesture &gesture);
    BuildStatus finish(std::shared_ptr<const Document> &outDocument);

private:
    enum class Scope : uint8_t { Paragraph, Span };

    std::unique_ptr<Document> document_;
    std::vector<Scope> scopes_;
    std::map<Gradient, int32_t> gradientIndices_;
    bool isInParagraph_ = false;

    BuildStatus requireOpen() const;
    BuildStatus requireParagraph() const;
};

// Shortest decimal form that round-trips; integral values print without a
// fraction.
std::string formatNumber(double value);

} // namespace atr
