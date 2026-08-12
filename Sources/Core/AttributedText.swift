// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import Foundation

public enum Attributed {
public protocol AttributedNode {
    func render(context: RenderContext) -> NodeRenderResult
}

public protocol AttributedBlock: AttributedNode {}

public protocol AttributedInline: AttributedNode {}

@resultBuilder
public enum AttributedTextBuilder {
    public static func buildBlock(
        _ components: [any AttributedBlock]...
    ) -> [any AttributedBlock] {
        components.flatMap { $0 }
    }

    public static func buildExpression<N: AttributedBlock>(
        _ expression: N
    ) -> [any AttributedBlock] {
        [expression]
    }

    public static func buildOptional(
        _ component: [any AttributedBlock]?
    ) -> [any AttributedBlock] {
        component ?? []
    }

    public static func buildEither(
        first component: [any AttributedBlock]
    ) -> [any AttributedBlock] {
        component
    }

    public static func buildEither(
        second component: [any AttributedBlock]
    ) -> [any AttributedBlock] {
        component
    }

    public static func buildArray(
        _ components: [[any AttributedBlock]]
    ) -> [any AttributedBlock] {
        components.flatMap { $0 }
    }
}

@resultBuilder
public enum AttributedInlineBuilder {
    public static func buildBlock(
        _ components: [any AttributedInline]...
    ) -> [any AttributedInline] {
        components.flatMap { $0 }
    }

    public static func buildExpression<N: AttributedInline>(
        _ expression: N
    ) -> [any AttributedInline] {
        [expression]
    }

    public static func buildExpression(
        _ expression: String
    ) -> [any AttributedInline] {
        [Text(expression)]
    }

    public static func buildOptional(
        _ component: [any AttributedInline]?
    ) -> [any AttributedInline] {
        component ?? []
    }

    public static func buildEither(
        first component: [any AttributedInline]
    ) -> [any AttributedInline] {
        component
    }

    public static func buildEither(
        second component: [any AttributedInline]
    ) -> [any AttributedInline] {
        component
    }

    public static func buildArray(
        _ components: [[any AttributedInline]]
    ) -> [any AttributedInline] {
        components.flatMap { $0 }
    }
}

public struct AttributedText {
    let children: [any AttributedBlock]

    public init(
        @AttributedTextBuilder content: () -> [any AttributedBlock]
    ) {
        children = content()
    }

    public func render() -> RenderedAttributedText {
        let interactions = InteractionRegistry()
        let context = RenderContext(
            textAttributes: TextAttributes.rootDefaults,
            paragraphAttributes: ParagraphAttributes(),
            interactions: interactions
        )
        let result = NSMutableAttributedString()

        for child in children {
            result.append(child.render(context: context).attributedString)
        }

        if result.string.last == "\n" {
            result.deleteCharacters(in: NSRange(location: result.length - 1, length: 1))
        }

        return RenderedAttributedText(
            attributedString: result,
            interactions: interactions
        )
    }
}

public struct RenderContext {
    var textAttributes: TextAttributes
    var paragraphAttributes: ParagraphAttributes
    let interactions: InteractionRegistry

    init(
        textAttributes: TextAttributes,
        paragraphAttributes: ParagraphAttributes,
        interactions: InteractionRegistry
    ) {
        self.textAttributes = textAttributes
        self.paragraphAttributes = paragraphAttributes
        self.interactions = interactions
    }
}

public struct NodeRenderResult {
    public let attributedString: NSAttributedString

    public init(attributedString: NSAttributedString) {
        self.attributedString = attributedString
    }
}

public final class RenderedAttributedText {
    public let attributedString: NSAttributedString
    let interactions: InteractionRegistry
    private var attachmentStorage: [AttachmentID: RenderedAttachment] = [:]
    private var loadingTasks: [AttachmentID: Task<Void, Never>] = [:]
    private var updateContinuations: [
        UUID: AsyncStream<RenderedTextUpdate>.Continuation
    ] = [:]

    init(
        attributedString: NSAttributedString,
        interactions: InteractionRegistry
    ) {
        self.attributedString = attributedString
        self.interactions = interactions
        registerAttachments()

        Task { @MainActor [weak self] in
            self?.startLoadingAttachments()
        }
    }

    deinit {
        loadingTasks.values.forEach { $0.cancel() }
        updateContinuations.values.forEach { $0.finish() }
    }

    public func interaction(for id: InteractionID) -> Interaction? {
        interactions.interaction(for: id)
    }

    @MainActor
    public var attachments: [RenderedAttachment] {
        attachmentStorage.values.sorted {
            $0.range.location < $1.range.location
        }
    }

    @MainActor
    public func attachment(for id: AttachmentID) -> RenderedAttachment? {
        attachmentStorage[id]
    }

    @MainActor
    public func updates() -> AsyncStream<RenderedTextUpdate> {
        let id = UUID()

        return AsyncStream { continuation in
            updateContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.updateContinuations[id] = nil
                }
            }
        }
    }

    @MainActor
    public func cancel() {
        for renderedAttachment in attachmentStorage.values {
            guard case .loading = renderedAttachment.state else {
                continue
            }

            loadingTasks[renderedAttachment.id]?.cancel()
            renderedAttachment.setState(.cancelled)
            emit(
                .attachmentStateChanged(
                    id: renderedAttachment.id,
                    range: renderedAttachment.range
                )
            )
        }

        loadingTasks.removeAll()
    }

    private func registerAttachments() {
        let fullRange = NSRange(location: 0, length: attributedString.length)

        attributedString.enumerateAttribute(
            .attributedAttachmentID,
            in: fullRange
        ) { [self] value, range, _ in
            guard
                let id = value as? AttachmentID,
                let attachment = attributedString.attribute(
                    .attachment,
                    at: range.location,
                    effectiveRange: nil
                ) as? ImageTextAttachment
            else {
                return
            }

            let state: AttachmentState = attachment.requiresLoading
                ? .loading
                : .resolved

            attachmentStorage[id] = RenderedAttachment(
                id: id,
                range: range,
                state: state,
                attachment: attachment
            )
        }
    }

    @MainActor
    private func startLoadingAttachments() {
        for renderedAttachment in attachmentStorage.values {
            guard case .loading = renderedAttachment.state else {
                continue
            }

            switch renderedAttachment.attachment.source {
            case .image:
                continue
            case let .async(loader):
                startLoading(renderedAttachment) {
                    try await loader()
                }
            case let .remote(url):
                startLoading(renderedAttachment) {
                    try await RemoteImageEnvironment.image(for: url)
                }
            }
        }
    }

    @MainActor
    private func startLoading(
        _ renderedAttachment: RenderedAttachment,
        loader: @escaping @Sendable () async throws -> PlatformImage
    ) {
        let id = renderedAttachment.id
        let task = Task { @MainActor [weak self, weak renderedAttachment] in
            do {
                let image = try await loader()
                try Task.checkCancellation()

                guard let renderedAttachment else {
                    return
                }

                self?.apply(image, to: renderedAttachment)
            } catch is CancellationError {
                self?.markCancelled(id: id)
            } catch {
                self?.markFailed(error, id: id)
            }
        }

        loadingTasks[id] = task
    }

    @MainActor
    private func apply(
        _ image: PlatformImage,
        to renderedAttachment: RenderedAttachment
    ) {
        guard image.size.width > 0, image.size.height > 0 else {
            markFailed(URLError(.cannotDecodeContentData), id: renderedAttachment.id)
            return
        }

        let attachment = renderedAttachment.attachment
        let oldSize = attachment.layoutSize(availableWidth: nil)
        attachment.resolve(with: image)
        attachment.bounds = attachment.layoutBounds(
            attributes: [:],
            availableWidth: nil
        )
        let newSize = attachment.layoutSize(availableWidth: nil)
        renderedAttachment.setState(.resolved)

        if oldSize == newSize {
            emit(
                .attachmentContentChanged(
                    id: renderedAttachment.id,
                    range: renderedAttachment.range
                )
            )
        } else {
            emit(
                .attachmentLayoutChanged(
                    id: renderedAttachment.id,
                    range: renderedAttachment.range
                )
            )
        }

        emit(
            .attachmentStateChanged(
                id: renderedAttachment.id,
                range: renderedAttachment.range
            )
        )
        loadingTasks[renderedAttachment.id] = nil
    }

    @MainActor
    private func markFailed(_ error: any Error, id: AttachmentID) {
        guard let renderedAttachment = attachmentStorage[id] else {
            return
        }

        renderedAttachment.setState(.failed(error))
        emit(
            .attachmentStateChanged(
                id: id,
                range: renderedAttachment.range
            )
        )
        loadingTasks[id] = nil
    }

    @MainActor
    private func markCancelled(id: AttachmentID) {
        guard let renderedAttachment = attachmentStorage[id] else {
            return
        }

        if case .cancelled = renderedAttachment.state {
            return
        }

        renderedAttachment.setState(.cancelled)
        emit(
            .attachmentStateChanged(
                id: id,
                range: renderedAttachment.range
            )
        )
        loadingTasks[id] = nil
    }

    @MainActor
    private func emit(_ update: RenderedTextUpdate) {
        updateContinuations.values.forEach { $0.yield(update) }
    }
}
}
