// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#include "DumpSupport.hpp"

#include <cmath>
#include <cstdio>
#include <cstdlib>

namespace atr {

namespace detail {

void appendUTF8(std::string &output, char32_t scalar) {
    if (scalar < 0x80) {
        output.push_back(static_cast<char>(scalar));
    } else if (scalar < 0x800) {
        output.push_back(static_cast<char>(0xC0 | (scalar >> 6)));
        output.push_back(static_cast<char>(0x80 | (scalar & 0x3F)));
    } else if (scalar < 0x10000) {
        output.push_back(static_cast<char>(0xE0 | (scalar >> 12)));
        output.push_back(static_cast<char>(0x80 | ((scalar >> 6) & 0x3F)));
        output.push_back(static_cast<char>(0x80 | (scalar & 0x3F)));
    } else {
        output.push_back(static_cast<char>(0xF0 | (scalar >> 18)));
        output.push_back(static_cast<char>(0x80 | ((scalar >> 12) & 0x3F)));
        output.push_back(static_cast<char>(0x80 | ((scalar >> 6) & 0x3F)));
        output.push_back(static_cast<char>(0x80 | (scalar & 0x3F)));
    }
}

std::string quoted(const char16_t *characters, size_t length) {
    std::string output = "\"";

    for (size_t index = 0; index < length; ++index) {
        char32_t scalar = characters[index];

        if (scalar >= 0xD800 && scalar <= 0xDBFF && index + 1 < length
            && characters[index + 1] >= 0xDC00 && characters[index + 1] <= 0xDFFF) {
            scalar = 0x10000 + ((scalar - 0xD800) << 10) + (characters[index + 1] - 0xDC00);
            ++index;
        } else if (scalar >= 0xD800 && scalar <= 0xDFFF) {
            scalar = 0xFFFD;
        }

        switch (scalar) {
        case '\\':
            output += "\\\\";
            break;
        case '"':
            output += "\\\"";
            break;
        case '\n':
            output += "\\n";
            break;
        case '\r':
            output += "\\r";
            break;
        case '\t':
            output += "\\t";
            break;
        default:
            if (scalar < 0x20 || scalar == 0x7F) {
                char buffer[16];
                std::snprintf(buffer, sizeof(buffer), "\\u{%X}", static_cast<unsigned>(scalar));
                output += buffer;
            } else {
                appendUTF8(output, scalar);
            }
        }
    }

    output += "\"";
    return output;
}

void appendField(std::string &fields, const std::string &field) {
    if (!fields.empty()) {
        fields += " ";
    }

    fields += field;
}

std::string describe(const Fill &fill) {
    return (fill.kind == FillKind::Color ? "c" : "g") + std::to_string(fill.index);
}

const char *name(UnderlineLines lines) {
    switch (lines) {
    case UnderlineLines::Single:
        return "single";
    case UnderlineLines::Double:
        return "double";
    }

    return "unknown";
}

const char *name(UnderlinePattern pattern) {
    switch (pattern) {
    case UnderlinePattern::Solid:
        return "solid";
    case UnderlinePattern::Dot:
        return "dot";
    case UnderlinePattern::Dash:
        return "dash";
    case UnderlinePattern::DashDot:
        return "dashDot";
    case UnderlinePattern::DashDotDot:
        return "dashDotDot";
    }

    return "unknown";
}

std::string describe(const Underline &underline) {
    std::string result = std::string(name(underline.lines)) + "," + name(underline.pattern);

    if (underline.thickness) {
        result += "," + formatNumber(*underline.thickness);
    }

    switch (underline.corners) {
    case UnderlineCorners::Square:
        break;
    case UnderlineCorners::Radius:
        result += ",radius=" + formatNumber(underline.cornerRadius);
        break;
    case UnderlineCorners::Capsule:
        result += ",capsule";
        break;
    }

    return result;
}

std::string describe(const TextStyle &style) {
    std::string fields;

    if (style.font) {
        appendField(fields, "font=f" + std::to_string(*style.font));
    }

    if (style.foreground) {
        appendField(fields, "fg=" + describe(*style.foreground));
    }

    if (style.backgroundColor) {
        appendField(fields, "bg=c" + std::to_string(*style.backgroundColor));
    }

    if (style.kern) {
        appendField(fields, "kern=" + formatNumber(*style.kern));
    }

    if (style.baselineOffset) {
        appendField(fields, "baseline=" + formatNumber(*style.baselineOffset));
    }

    if (style.underline) {
        appendField(fields, "underline=" + describe(*style.underline));
    }

    if (style.underlineFill) {
        appendField(fields, "underlineFill=" + describe(*style.underlineFill));
    }

    return "text{" + fields + "}";
}

const char *name(TextAlignment alignment) {
    switch (alignment) {
    case TextAlignment::Natural:
        return "natural";
    case TextAlignment::Left:
        return "left";
    case TextAlignment::Center:
        return "center";
    case TextAlignment::Right:
        return "right";
    case TextAlignment::Justified:
        return "justified";
    }

    return "unknown";
}

const char *name(WritingDirection direction) {
    switch (direction) {
    case WritingDirection::Natural:
        return "natural";
    case WritingDirection::LeftToRight:
        return "leftToRight";
    case WritingDirection::RightToLeft:
        return "rightToLeft";
    }

    return "unknown";
}

const char *name(GradientScope scope) {
    switch (scope) {
    case GradientScope::Line:
        return "line";
    case GradientScope::Paragraph:
        return "paragraph";
    case GradientScope::Document:
        return "document";
    }

    return "unknown";
}

std::string describe(const ParagraphStyle &style) {
    std::string fields;

    if (style.alignment) {
        appendField(fields, std::string("align=") + name(*style.alignment));
    }

    if (style.writingDirection) {
        appendField(fields, std::string("direction=") + name(*style.writingDirection));
    }

    if (style.lineSpacing) {
        appendField(fields, "lineSpacing=" + formatNumber(*style.lineSpacing));
    }

    if (style.paragraphSpacing) {
        appendField(fields, "paragraphSpacing=" + formatNumber(*style.paragraphSpacing));
    }

    return "paragraph{" + fields + "}";
}

std::string describe(const AttachmentDescriptor &descriptor) {
    if (descriptor.kind == AttachmentKind::Spacer) {
        return "spacer width=" + formatNumber(descriptor.width) + " height="
            + (descriptor.inferredHeight ? std::string("inferred") : formatNumber(descriptor.height));
    }

    std::string result = descriptor.pipeline == ImagePipeline::Image ? "image" : "asyncImage";

    if (descriptor.sizeKind == AttachmentSizeKind::Fixed) {
        result += " size=fixed(" + formatNumber(descriptor.width) + "x"
            + formatNumber(descriptor.height) + ")";
    } else {
        auto width = descriptor.maxWidth ? formatNumber(*descriptor.maxWidth) : "-";
        auto height = descriptor.maxHeight ? formatNumber(*descriptor.maxHeight) : "-";
        result += " size=adaptive(" + width + "x" + height + ")";
    }

    if (descriptor.contentWidth && descriptor.contentHeight) {
        result += " content=" + formatNumber(*descriptor.contentWidth) + "x"
            + formatNumber(*descriptor.contentHeight);
    }

    switch (descriptor.alignmentKind) {
    case AttachmentAlignmentKind::Baseline:
        result += " align=baseline";
        break;
    case AttachmentAlignmentKind::Center:
        result += " align=center";
        break;
    case AttachmentAlignmentKind::Top:
        result += " align=top";
        break;
    case AttachmentAlignmentKind::Bottom:
        result += " align=bottom";
        break;
    case AttachmentAlignmentKind::Offset:
        result += " align=offset(" + formatNumber(descriptor.alignmentOffset) + ")";
        break;
    }

    if (descriptor.accessibilityLabel) {
        const auto &label = *descriptor.accessibilityLabel;
        result += " label=" + quoted(label.data(), label.size());
    }

    return result;
}

std::string describe(const Gradient &gradient) {
    std::string result = "linear (" + formatNumber(gradient.startX) + ","
        + formatNumber(gradient.startY) + ")->(" + formatNumber(gradient.endX) + ","
        + formatNumber(gradient.endY) + ") [";

    for (size_t index = 0; index < gradient.colors.size(); ++index) {
        result += (index == 0 ? "c" : " c") + std::to_string(gradient.colors[index]);
    }

    result += "]";

    if (gradient.locations) {
        result += " @[";

        for (size_t index = 0; index < gradient.locations->size(); ++index) {
            result += (index == 0 ? "" : " ") + formatNumber((*gradient.locations)[index]);
        }

        result += "]";
    }

    return result + " scope=" + name(gradient.scope);
}

std::string describe(const Gesture &gesture) {
    if (gesture.kind == GestureKind::Tap) {
        return "tap(" + std::to_string(gesture.tapCount) + ")";
    }

    return "longPress(" + formatNumber(gesture.minimumPressDuration) + ")";
}

} // namespace detail

std::string formatNumber(double value) {
    if (std::isfinite(value) && std::rint(value) == value && std::fabs(value) < 1e15) {
        return std::to_string(static_cast<long long>(value));
    }

    char buffer[32];

    for (int precision = 1; precision <= 17; ++precision) {
        std::snprintf(buffer, sizeof(buffer), "%.*g", precision, value);

        if (std::strtod(buffer, nullptr) == value) {
            break;
        }
    }

    return buffer;
}

std::string Document::dump() const {
    using namespace detail;

    std::string output = "base " + describe(baseParagraphStyle_) + " " + describe(baseTextStyle_);
    size_t depth = 0;

    auto newLine = [&output](size_t indentDepth) {
        output += "\n";
        output.append(indentDepth * 2, ' ');
    };

    for (const auto &op : ops_) {
        switch (op.kind) {
        case OpKind::BeginParagraph:
            newLine(depth);
            output += "P " + describe(paragraphStyles_[op.first]) + " "
                + describe(textStyles_[op.second]);
            ++depth;
            break;
        case OpKind::EndParagraph:
            --depth;
            newLine(depth);
            output += "/P";
            break;
        case OpKind::PushSpan:
            newLine(depth);
            output += "SPAN";

            if (op.second != kNoInteraction) {
                output += " i" + std::to_string(op.second);
            }

            output += " " + describe(textStyles_[op.first]);
            ++depth;
            break;
        case OpKind::PopSpan:
            --depth;
            newLine(depth);
            output += "END";
            break;
        case OpKind::Text:
            newLine(depth);
            output += quoted(text_.data() + op.first, op.second);
            break;
        case OpKind::Attachment:
            newLine(depth);
            output += "ATTACH a" + std::to_string(op.first) + " "
                + describe(attachments_[op.first]);
            break;
        }
    }

    for (size_t index = 0; index < gradients_.size(); ++index) {
        output += "\ng" + std::to_string(index) + " = " + describe(gradients_[index]);
    }

    for (size_t index = 0; index < interactions_.size(); ++index) {
        output += "\ni" + std::to_string(index) + " = " + describe(interactions_[index]);
    }

    return output;
}

} // namespace atr
