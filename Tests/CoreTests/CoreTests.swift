// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import Foundation
import XCTest
@testable import AttributedCore

private typealias AttributedBlock = Attributed.AttributedBlock
private typealias RenderContext = Attributed.RenderContext
private typealias NodeRenderResult = Attributed.NodeRenderResult
private typealias AttributedText = Attributed.AttributedText
private typealias TextAttributes = Attributed.TextAttributes
private typealias ParagraphAttributes = Attributed.ParagraphAttributes
private typealias Paragraph = Attributed.Paragraph
private typealias Text = Attributed.Text
private typealias Link = Attributed.Link
private typealias InteractionID = Attributed.InteractionID
private typealias Image = Attributed.Image
private typealias ImageSource = Attributed.ImageSource

private struct TestBlock: AttributedBlock {
    func render(context: RenderContext) -> NodeRenderResult {
        NodeRenderResult(attributedString: NSAttributedString())
    }
}

final class CoreTests: XCTestCase {
    func testPlatformFontCanBeCreated() {
        let font = PlatformFont.systemFont(ofSize: 16)

        XCTAssertGreaterThan(font.pointSize, 0)
    }

    func testDocumentBuilderSupportsConditionalsAndLoops() {
        let includeExtra = true
        let document = AttributedText {
            TestBlock()

            if includeExtra {
                TestBlock()
            }

            for _ in 0..<2 {
                TestBlock()
            }
        }

        XCTAssertEqual(document.children.count, 4)
    }

    func testTextAttributesMergeAndConvertAllSupportedValues() {
        var parent = TextAttributes()
        parent.font = .systemFont(ofSize: 12)
        parent.foregroundColor = .black
        parent.kern = 1

        var child = TextAttributes()
        child.font = .boldSystemFont(ofSize: 16)
        child.underlineStyle = .single
        child.underlineColor = .blue

        let merged = parent.merging(child)
        let attributes = merged.nsAttributes

        XCTAssertEqual((attributes[.font] as? PlatformFont)?.pointSize, 16)
        XCTAssertNotNil(attributes[.foregroundColor] as? PlatformColor)
        XCTAssertEqual(attributes[.kern] as? CGFloat, 1)
        XCTAssertEqual(attributes[.underlineStyle] as? Int, NSUnderlineStyle.single.rawValue)
        XCTAssertNotNil(attributes[.underlineColor] as? PlatformColor)
    }

    func testParagraphAttributesMergeAndCreateStyle() {
        var parent = ParagraphAttributes()
        parent.alignment = .left
        parent.lineSpacing = 4

        var child = ParagraphAttributes()
        child.alignment = .center
        child.baseWritingDirection = .rightToLeft
        child.paragraphSpacing = 8

        let style = parent.merging(child).makeNSParagraphStyle()

        XCTAssertEqual(style.alignment, .center)
        XCTAssertEqual(style.baseWritingDirection, .rightToLeft)
        XCTAssertEqual(style.lineSpacing, 4)
        XCTAssertEqual(style.paragraphSpacing, 8)
    }

    func testRenderingInheritsAttributesAndRemovesFinalParagraphTerminator() {
        let content = AttributedText {
            Paragraph {
                "Hello "
                Text("World").font(.boldSystemFont(ofSize: 16))
            }
            .font(.systemFont(ofSize: 12))
            .foregroundColor(.black)
            .lineSpacing(4)

            Paragraph {
                "Second"
            }
            .alignment(.center)
        }

        let rendered = content.render().attributedString

        XCTAssertEqual(rendered.string, "Hello World\nSecond")
        XCTAssertEqual(
            (rendered.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont)?.pointSize,
            12
        )
        XCTAssertEqual(
            (rendered.attribute(.font, at: 6, effectiveRange: nil) as? PlatformFont)?.pointSize,
            16
        )
        XCTAssertEqual(
            (rendered.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.lineSpacing,
            4
        )
        XCTAssertEqual(
            (rendered.attribute(.paragraphStyle, at: rendered.length - 1, effectiveRange: nil) as? NSParagraphStyle)?.alignment,
            .center
        )
    }

    func testRenderingUsesSemanticDefaultForegroundColor() {
        let rendered = AttributedText {
            Paragraph {
                "Default color"
            }
        }.render()
        let color = rendered.attributedString.attribute(
            .foregroundColor,
            at: 0,
            effectiveRange: nil
        ) as? PlatformColor

        #if canImport(UIKit)
        XCTAssertTrue(color?.isEqual(PlatformColor.label) == true)
        #elseif canImport(AppKit)
        XCTAssertTrue(color?.isEqual(PlatformColor.labelColor) == true)
        #endif
    }

    func testLinkRegistersInteractionAndEmitsStandardURLAttribute() {
        let url = URL(string: "https://example.com")!
        let rendered = AttributedText {
            Paragraph {
                Link("Example", url: url)
            }
        }.render()

        let id = rendered.attributedString.attribute(
            .attributedInteractionID,
            at: 0,
            effectiveRange: nil
        ) as? InteractionID

        XCTAssertNotNil(id)
        XCTAssertEqual(
            rendered.attributedString.attribute(.link, at: 0, effectiveRange: nil) as? URL,
            url
        )

        guard let id, case let .url(registeredURL)? = rendered.interaction(for: id) else {
            return XCTFail("Expected the rendered link to be registered.")
        }

        XCTAssertEqual(registeredURL, url)
    }

    @MainActor
    func testSynchronousImageRendersAndRegistersAttachment() {
        let image = makeImage(size: CGSize(width: 40, height: 20))
        let rendered = AttributedText {
            Paragraph {
                "Before"
                Image(image)
                    .size(.fixed(width: 16, height: 12))
                    .alignment(.center)
                "After"
            }
            .font(.systemFont(ofSize: 18))
        }.render()

        XCTAssertEqual(rendered.attachments.count, 1)
        XCTAssertEqual(rendered.attachments[0].range, NSRange(location: 6, length: 1))
        XCTAssertEqual(
            rendered.attributedString.attribute(
                .attachment,
                at: 6,
                effectiveRange: nil
            ) as? NSTextAttachment,
            rendered.attachments[0].attachment
        )
        XCTAssertEqual(
            rendered.attachments[0].attachment.layoutSize(availableWidth: nil),
            CGSize(width: 16, height: 12)
        )
    }

    @MainActor
    func testAdaptiveImagePreservesAspectRatioWithoutUpscaling() {
        let image = makeImage(size: CGSize(width: 200, height: 100))
        let rendered = AttributedText {
            Paragraph {
                Image(image)
                    .size(.adaptive(maxWidth: 80, maxHeight: 80))
            }
        }.render()
        let attachment = rendered.attachments[0].attachment

        XCTAssertEqual(
            attachment.layoutSize(availableWidth: nil),
            CGSize(width: 80, height: 40)
        )
        XCTAssertEqual(
            attachment.layoutSize(availableWidth: 50),
            CGSize(width: 50, height: 25)
        )
    }

    @MainActor
    func testIntrinsicImageUsesImageSizeAndAlignmentUsesFontMetrics() {
        let image = makeImage(size: CGSize(width: 10, height: 8))
        let font = PlatformFont.systemFont(ofSize: 20)

        func attachment(
            alignment: Attributed.AttachmentAlignment
        ) -> Attributed.ImageTextAttachment {
            AttributedText {
                Paragraph {
                    Image(image)
                        .alignment(alignment)
                }
                .font(font)
            }.render().attachments[0].attachment
        }

        let baseline = attachment(alignment: .baseline)
        let center = attachment(alignment: .center)
        let top = attachment(alignment: .top)
        let bottom = attachment(alignment: .bottom)
        let offset = attachment(alignment: .offset(3))
        let attributes: [NSAttributedString.Key: Any] = [.font: font]

        XCTAssertEqual(
            baseline.layoutSize(availableWidth: nil),
            image.size
        )
        XCTAssertEqual(
            baseline.layoutBounds(
                attributes: attributes,
                availableWidth: nil
            ).origin.y,
            0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            center.layoutBounds(
                attributes: attributes,
                availableWidth: nil
            ).origin.y,
            (font.capHeight + font.descender - image.size.height) / 2,
            accuracy: 0.001
        )
        XCTAssertEqual(
            top.layoutBounds(
                attributes: attributes,
                availableWidth: nil
            ).origin.y,
            font.capHeight - image.size.height,
            accuracy: 0.001
        )
        XCTAssertEqual(
            bottom.layoutBounds(
                attributes: attributes,
                availableWidth: nil
            ).origin.y,
            font.descender,
            accuracy: 0.001
        )
        XCTAssertEqual(
            offset.layoutBounds(
                attributes: attributes,
                availableWidth: nil
            ).origin.y,
            3,
            accuracy: 0.001
        )
    }

    @MainActor
    func testAsyncImageEmitsLayoutThenStateUpdate() async {
        let gate = ImageGate()
        let placeholder = makeImage(size: CGSize(width: 10, height: 10))
        let resolvedImage = makeImage(size: CGSize(width: 40, height: 20))
        let rendered = AttributedText {
            Paragraph {
                Image(
                    source: ImageSource.async {
                        await gate.load()
                    },
                    placeholder: placeholder
                )
            }
        }.render()
        var updates = rendered.updates().makeAsyncIterator()

        await gate.resolve(resolvedImage)

        guard
            let first = await updates.next(),
            let second = await updates.next()
        else {
            return XCTFail("Expected attachment updates.")
        }

        guard case .attachmentLayoutChanged = first else {
            return XCTFail("Expected a layout update first.")
        }

        guard case .attachmentStateChanged = second else {
            return XCTFail("Expected a state update second.")
        }

        guard case .resolved = rendered.attachments[0].state else {
            return XCTFail("Expected a resolved attachment.")
        }
    }

    @MainActor
    func testFixedAsyncImageEmitsContentUpdate() async {
        let gate = ImageGate()
        let rendered = AttributedText {
            Paragraph {
                Image(
                    source: .async {
                        await gate.load()
                    }
                )
                .size(.fixed(width: 24, height: 24))
            }
        }.render()
        var updates = rendered.updates().makeAsyncIterator()

        await gate.resolve(makeImage(size: CGSize(width: 80, height: 40)))

        guard let first = await updates.next() else {
            return XCTFail("Expected an attachment update.")
        }

        guard case .attachmentContentChanged = first else {
            return XCTFail("Expected a content update for fixed bounds.")
        }
    }

    @MainActor
    func testCancellingBeforeLoadingStartsMarksAttachmentCancelled() async {
        let gate = ImageGate()
        let rendered = AttributedText {
            Paragraph {
                Image(
                    source: .async {
                        await gate.load()
                    }
                )
            }
        }.render()
        var updates = rendered.updates().makeAsyncIterator()

        rendered.cancel()

        guard let update = await updates.next() else {
            return XCTFail("Expected a cancellation update.")
        }

        guard case .attachmentStateChanged = update else {
            return XCTFail("Expected a state update.")
        }

        guard case .cancelled = rendered.attachments[0].state else {
            return XCTFail("Expected a cancelled attachment.")
        }
    }

    @MainActor
    func testRemoteImageUsesInjectedProvider() async {
        let image = makeImage(size: CGSize(width: 30, height: 15))
        Attributed.RemoteImageEnvironment.provider = RemoteImageStub(
            image: image
        )
        defer {
            Attributed.RemoteImageEnvironment.provider = nil
        }

        let rendered = AttributedText {
            Paragraph {
                Image(remoteURL: URL(string: "https://example.com/image.png")!)
            }
        }.render()
        var updates = rendered.updates().makeAsyncIterator()

        _ = await updates.next()
        _ = await updates.next()

        guard case .resolved = rendered.attachments[0].state else {
            return XCTFail("Expected the remote image to resolve.")
        }
    }

    @MainActor
    func testRemoteImageUsesSynchronousCachedImageWithoutAsyncLoading() async {
        let image = makeImage(size: CGSize(width: 44, height: 22))
        let provider = CachedRemoteImageStub(image: image)
        Attributed.RemoteImageEnvironment.provider = provider
        defer {
            Attributed.RemoteImageEnvironment.provider = nil
        }

        let rendered = AttributedText {
            Paragraph {
                Image(remoteURL: URL(string: "https://example.com/cached.png")!)
            }
        }.render()

        guard case .resolved = rendered.attachments[0].state else {
            return XCTFail("Expected the cached image to resolve synchronously.")
        }

        XCTAssertTrue(rendered.attachments[0].attachment.image === image)
        await Task.yield()
        XCTAssertEqual(provider.asyncRequestCount, 0)
    }

    @MainActor
    func testRemoteCacheErrorFallsBackToAsyncLoading() async {
        let image = makeImage(size: CGSize(width: 36, height: 18))
        let provider = ThrowingCacheRemoteImageStub(image: image)
        Attributed.RemoteImageEnvironment.provider = provider
        defer {
            Attributed.RemoteImageEnvironment.provider = nil
        }

        let rendered = AttributedText {
            Paragraph {
                Image(remoteURL: URL(string: "https://example.com/fallback.png")!)
            }
        }.render()
        var updates = rendered.updates().makeAsyncIterator()

        _ = await updates.next()
        _ = await updates.next()

        guard case .resolved = rendered.attachments[0].state else {
            return XCTFail("Expected async loading after a cache error.")
        }

        XCTAssertEqual(provider.asyncRequestCount, 1)
    }

    @MainActor
    func testAsyncImageFailureKeepsPlaceholder() async {
        let placeholder = makeImage(size: CGSize(width: 12, height: 12))
        let rendered = AttributedText {
            Paragraph {
                Image(
                    source: .async {
                        throw ImageTestError.failed
                    },
                    placeholder: placeholder
                )
            }
        }.render()
        var updates = rendered.updates().makeAsyncIterator()

        guard let update = await updates.next() else {
            return XCTFail("Expected a failure state update.")
        }

        guard case .attachmentStateChanged = update else {
            return XCTFail("Expected a state update.")
        }

        guard case .failed = rendered.attachments[0].state else {
            return XCTFail("Expected a failed attachment.")
        }

        XCTAssertTrue(rendered.attachments[0].attachment.image === placeholder)
    }

    @MainActor
    func testAsyncImageWithoutPlaceholderUsesLoadingIndicatorBounds() {
        let rendered = AttributedText {
            Paragraph {
                Image(
                    source: .async {
                        await ImageGate().load()
                    }
                )
            }
        }.render()
        let attachment = rendered.attachments[0].attachment

        XCTAssertTrue(attachment.usesTextAttachmentView)
        XCTAssertEqual(
            attachment.layoutSize(availableWidth: nil),
            CGSize(width: 24, height: 24)
        )
        rendered.cancel()
    }

    @MainActor
    func testAsyncImageWithPlaceholderDoesNotUseLoadingIndicatorView() {
        let placeholder = makeImage(size: CGSize(width: 18, height: 12))
        let rendered = AttributedText {
            Paragraph {
                Image(
                    source: .async {
                        await ImageGate().load()
                    },
                    placeholder: placeholder
                )
            }
        }.render()
        let attachment = rendered.attachments[0].attachment

        XCTAssertFalse(attachment.usesTextAttachmentView)
        XCTAssertEqual(attachment.layoutSize(availableWidth: nil), placeholder.size)
        rendered.cancel()
    }
}

private enum ImageTestError: Error {
    case failed
}

private actor ImageGate {
    private var image: PlatformImage?
    private var continuation: CheckedContinuation<PlatformImage, Never>?

    func load() async -> PlatformImage {
        if let image {
            return image
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resolve(_ image: PlatformImage) {
        if let continuation {
            self.continuation = nil
            continuation.resume(returning: image)
        } else {
            self.image = image
        }
    }
}

private actor RemoteImageStub: Attributed.RemoteImageProvider {
    let imageValue: PlatformImage

    init(image: PlatformImage) {
        imageValue = image
    }

    func image(for url: URL) async throws -> PlatformImage {
        imageValue
    }
}

private final class CachedRemoteImageStub: Attributed.RemoteImageProvider, @unchecked Sendable {
    let imageValue: PlatformImage
    private let lock = NSLock()
    private var storedAsyncRequestCount = 0

    var asyncRequestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedAsyncRequestCount
    }

    init(image: PlatformImage) {
        imageValue = image
    }

    func cachedImage(for url: URL) throws -> PlatformImage? {
        imageValue
    }

    func image(for url: URL) async throws -> PlatformImage {
        recordAsyncRequest()
        return imageValue
    }

    private func recordAsyncRequest() {
        lock.lock()
        storedAsyncRequestCount += 1
        lock.unlock()
    }
}

private final class ThrowingCacheRemoteImageStub: Attributed.RemoteImageProvider, @unchecked Sendable {
    let imageValue: PlatformImage
    private let lock = NSLock()
    private var storedAsyncRequestCount = 0

    var asyncRequestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedAsyncRequestCount
    }

    init(image: PlatformImage) {
        imageValue = image
    }

    func cachedImage(for url: URL) throws -> PlatformImage? {
        throw ImageTestError.failed
    }

    func image(for url: URL) async throws -> PlatformImage {
        recordAsyncRequest()
        return imageValue
    }

    private func recordAsyncRequest() {
        lock.lock()
        storedAsyncRequestCount += 1
        lock.unlock()
    }
}

private func makeImage(size: CGSize) -> PlatformImage {
    #if canImport(UIKit)
    UIGraphicsImageRenderer(size: size).image { _ in }
    #elseif canImport(AppKit)
    NSImage(size: size)
    #endif
}
