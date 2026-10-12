// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#include "atr/Resolve.hpp"

#include <algorithm>
#include <functional>
#include <map>
#include <set>
#include <unordered_map>

#include "DumpSupport.hpp"

namespace atr {

bool ResolvedTextStyle::operator==(const ResolvedTextStyle &other) const {
    return font == other.font && foreground == other.foreground
        && backgroundColor == other.backgroundColor && kern == other.kern
        && baselineOffset == other.baselineOffset && underline == other.underline
        && underlineFill == other.underlineFill && interactionSet == other.interactionSet;
}

namespace {

template <typename T> void combine(size_t &seed, const T &value) {
    seed ^= std::hash<T>{}(value) + 0x9E3779B97F4A7C15ULL + (seed << 6) + (seed >> 2);
}

struct ResolvedTextStyleHash {
    size_t operator()(const ResolvedTextStyle &style) const {
        size_t seed = 0;
        combine(seed, style.font);
        combine(seed, static_cast<int>(style.foreground.kind));
        combine(seed, style.foreground.index);
        combine(seed, style.backgroundColor.value_or(-1));
        combine(seed, style.kern);
        combine(seed, style.baselineOffset);
        combine(seed, style.underline.has_value());
        combine(seed, style.interactionSet);
        return seed;
    }
};

TextStyle merged(const TextStyle &parent, const TextStyle &child) {
    TextStyle result = parent;

    if (child.font) {
        result.font = child.font;
    }

    if (child.foreground) {
        result.foreground = child.foreground;
    }

    if (child.backgroundColor) {
        result.backgroundColor = child.backgroundColor;
    }

    if (child.kern) {
        result.kern = child.kern;
    }

    if (child.baselineOffset) {
        result.baselineOffset = child.baselineOffset;
    }

    if (child.underline) {
        result.underline = child.underline;
    }

    if (child.underlineFill) {
        result.underlineFill = child.underlineFill;
    }

    return result;
}

ParagraphStyle merged(const ParagraphStyle &parent, const ParagraphStyle &child) {
    ParagraphStyle result = parent;

    if (child.alignment) {
        result.alignment = child.alignment;
    }

    if (child.writingDirection) {
        result.writingDirection = child.writingDirection;
    }

    if (child.lineSpacing) {
        result.lineSpacing = child.lineSpacing;
    }

    if (child.paragraphSpacing) {
        result.paragraphSpacing = child.paragraphSpacing;
    }

    return result;
}

bool isStrongRightToLeft(char32_t scalar) {
    return (scalar >= 0x0590 && scalar <= 0x08FF) || (scalar >= 0xFB1D && scalar <= 0xFDFF)
        || (scalar >= 0xFE70 && scalar <= 0xFEFF) || (scalar >= 0x10800 && scalar <= 0x10FFF)
        || (scalar >= 0x1E800 && scalar <= 0x1EFFF);
}

bool isStrongLeftToRight(char32_t scalar) {
    return (scalar >= 'A' && scalar <= 'Z') || (scalar >= 'a' && scalar <= 'z')
        || (scalar >= 0x00C0 && scalar <= 0x02AF && scalar != 0x00D7 && scalar != 0x00F7)
        || (scalar >= 0x0370 && scalar <= 0x058F) || (scalar >= 0x0900 && scalar <= 0x1FFF)
        || (scalar >= 0x3040 && scalar <= 0x9FFF) || (scalar >= 0xAC00 && scalar <= 0xD7AF);
}

// Approximates the Unicode first-strong rule with the scripts' block ranges,
// avoiding a Unicode property database. Characters outside the listed blocks
// are treated as neutral.
WritingDirection firstStrongDirection(const std::u16string &text) {
    for (size_t index = 0; index < text.size(); ++index) {
        char32_t scalar = text[index];

        if (scalar >= 0xD800 && scalar <= 0xDBFF && index + 1 < text.size()) {
            scalar = 0x10000 + ((scalar - 0xD800) << 10) + (text[index + 1] - 0xDC00);
            ++index;
        }

        if (isStrongRightToLeft(scalar)) {
            return WritingDirection::RightToLeft;
        }

        if (isStrongLeftToRight(scalar)) {
            return WritingDirection::LeftToRight;
        }
    }

    return WritingDirection::LeftToRight;
}

class Resolver {
public:
    explicit Resolver(const Document &document) : document_(document) {}

    ResolvedDocument run() {
        textStack_.push_back(document_.baseTextStyle());
        interactionStack_.push_back(kNoInteraction);
        result_.interactionRanges.resize(document_.interactions().size());
        interactionStarts_.resize(document_.interactions().size());

        for (const auto &op : document_.ops()) {
            switch (op.kind) {
            case OpKind::BeginParagraph:
                beginParagraph(op);
                break;
            case OpKind::EndParagraph:
                endParagraph();
                break;
            case OpKind::PushSpan:
                pushScope(document_.textStyles()[op.first], op.second);
                break;
            case OpKind::PopSpan:
                popScope();
                break;
            case OpKind::Text:
                appendText(op);
                break;
            case OpKind::Attachment:
                appendAttachment(op.first);
                break;
            }
        }

        return std::move(result_);
    }

private:
    const Document &document_;
    ResolvedDocument result_;
    std::unordered_map<ResolvedTextStyle, uint32_t, ResolvedTextStyleHash> styleIndices_;
    std::vector<TextStyle> textStack_;
    std::vector<uint32_t> interactionStack_;
    std::map<std::vector<uint32_t>, uint32_t> setIndices_;
    ResolvedParagraph *paragraph_ = nullptr;
    ParagraphStyle paragraphStyle_;
    // Document text offsets: where the current paragraph starts, and where
    // the last finished paragraph ends.
    uint32_t paragraphStart_ = 0;
    uint32_t finishedEnd_ = 0;
    uint32_t finishedCount_ = 0;
    std::vector<uint32_t> interactionStarts_;

    uint32_t nextParagraphStart() const {
        return finishedCount_ > 0 ? finishedEnd_ + 1 : 0;
    }

    // A span opened between paragraphs starts after the separator that will
    // precede its first paragraph, and one closed there ends before it.
    uint32_t spanStart() const {
        return paragraph_ ? paragraphStart_ + static_cast<uint32_t>(paragraph_->text.size())
                          : nextParagraphStart();
    }

    uint32_t spanEnd() const {
        return paragraph_ ? paragraphStart_ + static_cast<uint32_t>(paragraph_->text.size())
                          : finishedEnd_;
    }

    void pushScope(const TextStyle &style, uint32_t interaction) {
        if (interaction != kNoInteraction) {
            interactionStarts_[interaction] = spanStart();
        }

        textStack_.push_back(merged(textStack_.back(), style));
        interactionStack_.push_back(interaction);
    }

    uint32_t currentInteractionSet() {
        std::vector<uint32_t> set;
        std::set<std::pair<GestureKind, uint32_t>> keys;

        for (auto scope = interactionStack_.rbegin(); scope != interactionStack_.rend(); ++scope) {
            if (*scope == kNoInteraction) {
                continue;
            }

            if (keys.insert(document_.interactions()[*scope].key()).second) {
                set.push_back(*scope);
            }
        }

        if (set.empty()) {
            return kNoInteractionSet;
        }

        if (auto found = setIndices_.find(set); found != setIndices_.end()) {
            return found->second;
        }

        auto index = static_cast<uint32_t>(result_.interactionSets.size());
        result_.interactionSets.push_back(set);
        setIndices_.emplace(std::move(set), index);
        return index;
    }

    void popScope() {
        uint32_t interaction = interactionStack_.back();

        if (interaction != kNoInteraction) {
            uint32_t start = interactionStarts_[interaction];
            uint32_t end = std::max(start, spanEnd());
            result_.interactionRanges[interaction] = {start, end - start};
        }

        textStack_.pop_back();
        interactionStack_.pop_back();
    }

    void beginParagraph(const Op &op) {
        pushScope(document_.textStyles()[op.second], kNoInteraction);
        paragraphStart_ = nextParagraphStart();
        paragraphStyle_ = merged(
            document_.baseParagraphStyle(),
            document_.paragraphStyles()[op.first]
        );
        result_.paragraphs.emplace_back();
        paragraph_ = &result_.paragraphs.back();
        paragraph_->paragraphTextStyle = currentStyle();
    }

    void endParagraph() {
        ResolvedParagraphStyle &style = paragraph_->style;
        style.alignment = paragraphStyle_.alignment.value_or(TextAlignment::Natural);
        auto direction = paragraphStyle_.writingDirection.value_or(WritingDirection::Natural);
        style.direction = direction == WritingDirection::Natural
            ? firstStrongDirection(paragraph_->text)
            : direction;
        style.lineSpacing = paragraphStyle_.lineSpacing.value_or(0);
        style.paragraphSpacing = paragraphStyle_.paragraphSpacing.value_or(0);
        finishedEnd_ = paragraphStart_ + static_cast<uint32_t>(paragraph_->text.size());
        finishedCount_ += 1;
        paragraph_ = nullptr;
        popScope();
    }

    void appendText(const Op &op) {
        uint32_t style = currentStyle();
        auto location = static_cast<uint32_t>(paragraph_->text.size());
        paragraph_->text.append(document_.text(), op.first, op.second);

        auto &runs = paragraph_->runs;

        if (!runs.empty() && runs.back().style == style && !runs.back().attachment) {
            runs.back().length += op.second;
            return;
        }

        runs.push_back({location, op.second, style, std::nullopt});
    }

    void appendAttachment(uint32_t attachment) {
        auto location = static_cast<uint32_t>(paragraph_->text.size());
        paragraph_->text.push_back(kAttachmentCharacter);
        paragraph_->runs.push_back({location, 1, currentStyle(), attachment});
    }

    uint32_t currentStyle() {
        const TextStyle &style = textStack_.back();
        ResolvedTextStyle resolved;
        resolved.font = style.font.value_or(kDefaultFont);
        resolved.foreground = style.foreground.value_or(Fill{});
        resolved.backgroundColor = style.backgroundColor;
        resolved.kern = style.kern.value_or(0);
        resolved.baselineOffset = style.baselineOffset.value_or(0);
        resolved.underline = style.underline;

        if (style.underline) {
            resolved.underlineFill = style.underlineFill.value_or(resolved.foreground);
        }

        resolved.interactionSet = currentInteractionSet();

        if (auto found = styleIndices_.find(resolved); found != styleIndices_.end()) {
            return found->second;
        }

        auto index = static_cast<uint32_t>(result_.styles.size());
        result_.styles.push_back(resolved);
        styleIndices_.emplace(resolved, index);
        return index;
    }
};

} // namespace

ResolvedDocument resolve(const Document &document) {
    return Resolver(document).run();
}

std::u16string ResolvedDocument::text(uint32_t location, uint32_t length) const {
    std::u16string full;

    for (size_t index = 0; index < paragraphs.size(); ++index) {
        if (index > 0) {
            full.push_back(u'\n');
        }

        full += paragraphs[index].text;
    }

    if (location >= full.size()) {
        return {};
    }

    return full.substr(location, length);
}

std::string ResolvedDocument::dump() const {
    using namespace detail;

    std::string output;

    for (size_t index = 0; index < styles.size(); ++index) {
        const auto &style = styles[index];
        std::string fields = style.font == kDefaultFont
            ? "font=default"
            : "font=f" + std::to_string(style.font);
        appendField(fields, "fg=" + describe(style.foreground));

        if (style.backgroundColor) {
            appendField(fields, "bg=c" + std::to_string(*style.backgroundColor));
        }

        if (style.kern != 0) {
            appendField(fields, "kern=" + formatNumber(style.kern));
        }

        if (style.baselineOffset != 0) {
            appendField(fields, "baseline=" + formatNumber(style.baselineOffset));
        }

        if (style.underline) {
            appendField(fields, "underline=" + describe(*style.underline));
            appendField(fields, "underlineFill=" + describe(*style.underlineFill));
        }

        if (style.interactionSet != kNoInteractionSet) {
            std::string ids;

            for (uint32_t interaction : interactionSets[style.interactionSet]) {
                ids += (ids.empty() ? "" : ",") + std::to_string(interaction);
            }

            appendField(fields, "i=[" + ids + "]");
        }

        output += (index == 0 ? "s" : "\ns") + std::to_string(index) + " = " + fields;
    }

    for (size_t index = 0; index < paragraphs.size(); ++index) {
        const auto &paragraph = paragraphs[index];
        output += "\nP" + std::to_string(index) + " align=" + name(paragraph.style.alignment)
            + " direction=" + name(paragraph.style.direction)
            + " lineSpacing=" + formatNumber(paragraph.style.lineSpacing)
            + " paragraphSpacing=" + formatNumber(paragraph.style.paragraphSpacing)
            + " s" + std::to_string(paragraph.paragraphTextStyle);

        for (const auto &run : paragraph.runs) {
            output += "\n  [" + std::to_string(run.location) + "," + std::to_string(run.length)
                + ") s" + std::to_string(run.style) + " ";

            if (run.attachment) {
                output += "a" + std::to_string(*run.attachment);
            } else {
                output += quoted(paragraph.text.data() + run.location, run.length);
            }
        }
    }

    return output;
}

} // namespace atr
