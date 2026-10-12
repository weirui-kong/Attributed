// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#include "atr/Document.hpp"

#include <tuple>

namespace atr {

bool Gradient::operator<(const Gradient &other) const {
    return std::tie(colors, locations, startX, startY, endX, endY, scope)
        < std::tie(
            other.colors,
            other.locations,
            other.startX,
            other.startY,
            other.endX,
            other.endY,
            other.scope
        );
}

const char *describe(BuildStatus status) {
    switch (status) {
    case BuildStatus::Ok:
        return "ok";
    case BuildStatus::NestedParagraph:
        return "Paragraphs cannot be nested.";
    case BuildStatus::ContentOutsideParagraph:
        return "Inline content must be added inside a paragraph.";
    case BuildStatus::MismatchedScope:
        return "A scope was closed out of order.";
    case BuildStatus::UnclosedScope:
        return "The document was finished with an open scope.";
    case BuildStatus::UnknownInteraction:
        return "A span refers to an interaction that was never registered.";
    case BuildStatus::AlreadyFinished:
        return "The document builder was already finished.";
    }

    return "unknown";
}

DocumentBuilder::DocumentBuilder() : document_(std::make_unique<Document>()) {}

void DocumentBuilder::setBaseTextStyle(const TextStyle &style) {
    if (document_) {
        document_->baseTextStyle_ = style;
    }
}

BuildStatus DocumentBuilder::beginParagraph(
    const ParagraphStyle &paragraphStyle,
    const TextStyle &textStyle
) {
    if (auto status = requireOpen(); status != BuildStatus::Ok) {
        return status;
    }

    if (isInParagraph_) {
        return BuildStatus::NestedParagraph;
    }

    auto paragraphIndex = static_cast<uint32_t>(document_->paragraphStyles_.size());
    auto textIndex = static_cast<uint32_t>(document_->textStyles_.size());
    document_->paragraphStyles_.push_back(paragraphStyle);
    document_->textStyles_.push_back(textStyle);
    document_->ops_.push_back({OpKind::BeginParagraph, paragraphIndex, textIndex});
    scopes_.push_back(Scope::Paragraph);
    isInParagraph_ = true;
    return BuildStatus::Ok;
}

BuildStatus DocumentBuilder::endParagraph() {
    if (auto status = requireOpen(); status != BuildStatus::Ok) {
        return status;
    }

    if (scopes_.empty() || scopes_.back() != Scope::Paragraph) {
        return BuildStatus::MismatchedScope;
    }

    scopes_.pop_back();
    document_->ops_.push_back({OpKind::EndParagraph, 0, 0});
    isInParagraph_ = false;
    return BuildStatus::Ok;
}

BuildStatus DocumentBuilder::pushSpan(const TextStyle &textStyle, uint32_t interaction) {
    if (auto status = requireOpen(); status != BuildStatus::Ok) {
        return status;
    }

    if (interaction != kNoInteraction && interaction >= document_->interactions_.size()) {
        return BuildStatus::UnknownInteraction;
    }

    auto textIndex = static_cast<uint32_t>(document_->textStyles_.size());
    document_->textStyles_.push_back(textStyle);
    document_->ops_.push_back({OpKind::PushSpan, textIndex, interaction});
    scopes_.push_back(Scope::Span);
    return BuildStatus::Ok;
}

BuildStatus DocumentBuilder::popSpan() {
    if (auto status = requireOpen(); status != BuildStatus::Ok) {
        return status;
    }

    if (scopes_.empty() || scopes_.back() != Scope::Span) {
        return BuildStatus::MismatchedScope;
    }

    scopes_.pop_back();
    document_->ops_.push_back({OpKind::PopSpan, 0, 0});
    return BuildStatus::Ok;
}

BuildStatus DocumentBuilder::appendText(const char16_t *characters, size_t length) {
    if (auto status = requireParagraph(); status != BuildStatus::Ok) {
        return status;
    }

    if (length == 0) {
        return BuildStatus::Ok;
    }

    auto offset = static_cast<uint32_t>(document_->text_.size());
    document_->text_.append(characters, length);
    document_->ops_.push_back({OpKind::Text, offset, static_cast<uint32_t>(length)});
    return BuildStatus::Ok;
}

BuildStatus DocumentBuilder::appendAttachment(
    const AttachmentDescriptor &descriptor,
    uint32_t &outID
) {
    if (auto status = requireParagraph(); status != BuildStatus::Ok) {
        return status;
    }

    outID = static_cast<uint32_t>(document_->attachments_.size());
    document_->attachments_.push_back(descriptor);
    document_->ops_.push_back({OpKind::Attachment, outID, 0});
    return BuildStatus::Ok;
}

uint32_t DocumentBuilder::registerInteraction(const Gesture &gesture) {
    if (!document_) {
        return kNoInteraction;
    }

    document_->interactions_.push_back(gesture);
    return static_cast<uint32_t>(document_->interactions_.size() - 1);
}

int32_t DocumentBuilder::registerGradient(const Gradient &gradient) {
    if (!document_) {
        return -1;
    }

    if (auto found = gradientIndices_.find(gradient); found != gradientIndices_.end()) {
        return found->second;
    }

    auto index = static_cast<int32_t>(document_->gradients_.size());
    document_->gradients_.push_back(gradient);
    gradientIndices_.emplace(gradient, index);
    return index;
}

BuildStatus DocumentBuilder::finish(std::shared_ptr<const Document> &outDocument) {
    if (auto status = requireOpen(); status != BuildStatus::Ok) {
        return status;
    }

    if (!scopes_.empty()) {
        return BuildStatus::UnclosedScope;
    }

    outDocument = std::move(document_);
    return BuildStatus::Ok;
}

BuildStatus DocumentBuilder::requireOpen() const {
    return document_ ? BuildStatus::Ok : BuildStatus::AlreadyFinished;
}

BuildStatus DocumentBuilder::requireParagraph() const {
    if (auto status = requireOpen(); status != BuildStatus::Ok) {
        return status;
    }

    return isInParagraph_ ? BuildStatus::Ok : BuildStatus::ContentOutsideParagraph;
}

} // namespace atr
