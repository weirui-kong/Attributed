// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public extension Attributed {
struct AttachmentID: Hashable {
    public let rawValue: UUID

    init() {
        rawValue = UUID()
    }
}

enum AttachmentSize: Equatable {
    case intrinsic
    case fixed(width: CGFloat, height: CGFloat)
    case adaptive(maxWidth: CGFloat?, maxHeight: CGFloat?)
}

enum AttachmentAlignment: Equatable {
    case baseline
    case center
    case top
    case bottom
    case offset(CGFloat)
}

enum ImageSource {
    case image(PlatformImage)
    case async(@Sendable () async throws -> PlatformImage)
    case remote(URL)
}

struct Image: AttributedInline {
    let source: ImageSource
    let placeholder: PlatformImage?
    let accessibilityLabel: String?
    var sizePolicy = AttachmentSize.intrinsic
    var alignmentPolicy = AttachmentAlignment.baseline

    public init(
        _ image: PlatformImage,
        accessibilityLabel: String? = nil
    ) {
        source = .image(image)
        placeholder = nil
        self.accessibilityLabel = Self.normalized(accessibilityLabel)
    }

    public init(
        source: ImageSource,
        placeholder: PlatformImage? = nil,
        accessibilityLabel: String? = nil
    ) {
        self.source = source
        self.placeholder = placeholder
        self.accessibilityLabel = Self.normalized(accessibilityLabel)
    }

    public init(
        remoteURL: URL,
        placeholder: PlatformImage? = nil,
        accessibilityLabel: String? = nil
    ) {
        source = .remote(remoteURL)
        self.placeholder = placeholder
        self.accessibilityLabel = Self.normalized(accessibilityLabel)
    }

    public func size(_ value: AttachmentSize) -> Self {
        var copy = self
        copy.sizePolicy = value
        return copy
    }

    public func alignment(_ value: AttachmentAlignment) -> Self {
        var copy = self
        copy.alignmentPolicy = value
        return copy
    }

    public func render(context: RenderContext) -> NodeRenderResult {
        validate(sizePolicy)

        let initialImage: PlatformImage?
        let requiresLoading: Bool

        switch source {
        case let .image(image):
            initialImage = image
            requiresLoading = false
        case .async:
            initialImage = placeholder
            requiresLoading = true
        case let .remote(url):
            // Cache lookup errors fall through to the regular asynchronous load.
            let cachedImage: PlatformImage? = (
                try? RemoteImageEnvironment.cachedImage(for: url)
            )
                .flatMap { image in
                    guard image.size.width > 0, image.size.height > 0 else {
                        return nil
                    }
                    return image
                }
            initialImage = cachedImage ?? placeholder
            requiresLoading = cachedImage == nil
        }

        let id = AttachmentID()
        let attachment = ImageTextAttachment(
            id: id,
            source: source,
            image: initialImage,
            sizePolicy: sizePolicy,
            alignmentPolicy: alignmentPolicy,
            accessibilityLabel: accessibilityLabel,
            requiresLoading: requiresLoading
        )
        let result = NSMutableAttributedString(attachment: attachment)
        let range = NSRange(location: 0, length: result.length)

        result.addAttributes(context.textAttributes.nsAttributes, range: range)
        result.addAttribute(.attributedAttachmentID, value: id, range: range)
        return NodeRenderResult(attributedString: result)
    }

    private static func normalized(_ label: String?) -> String? {
        guard let label, !label.isEmpty else {
            return nil
        }

        return label
    }

    private func validate(_ size: AttachmentSize) {
        switch size {
        case .intrinsic:
            break
        case let .fixed(width, height):
            precondition(width.isFinite && width > 0)
            precondition(height.isFinite && height > 0)
        case let .adaptive(maxWidth, maxHeight):
            precondition(maxWidth != nil || maxHeight != nil)

            if let maxWidth {
                precondition(maxWidth.isFinite && maxWidth > 0)
            }

            if let maxHeight {
                precondition(maxHeight.isFinite && maxHeight > 0)
            }
        }
    }
}
}

extension Attributed {
final class ImageTextAttachment: NSTextAttachment {
    let id: AttachmentID
    let source: ImageSource
    let sizePolicy: AttachmentSize
    let alignmentPolicy: AttachmentAlignment
    let imageAccessibilityLabel: String?
    let requiresLoading: Bool

    init(
        id: AttachmentID,
        source: ImageSource,
        image: PlatformImage?,
        sizePolicy: AttachmentSize,
        alignmentPolicy: AttachmentAlignment,
        accessibilityLabel: String?,
        requiresLoading: Bool
    ) {
        self.id = id
        self.source = source
        self.sizePolicy = sizePolicy
        self.alignmentPolicy = alignmentPolicy
        imageAccessibilityLabel = accessibilityLabel
        self.requiresLoading = requiresLoading
        super.init(data: nil, ofType: nil)
        self.image = image
        bounds = layoutBounds(attributes: [:], availableWidth: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func attachmentBounds(
        for attributes: [NSAttributedString.Key: Any],
        location: any NSTextLocation,
        textContainer: NSTextContainer?,
        proposedLineFragment: CGRect,
        position: CGPoint
    ) -> CGRect {
        layoutBounds(
            attributes: attributes,
            availableWidth: proposedLineFragment.width
        )
    }

    override var usesTextAttachmentView: Bool {
        false
    }

    func resolve(with image: PlatformImage) {
        self.image = image
    }

    func layoutBounds(
        attributes: [NSAttributedString.Key: Any],
        availableWidth: CGFloat?
    ) -> CGRect {
        let size = layoutSize(availableWidth: availableWidth)
        let font = attributes[.font] as? PlatformFont ?? defaultFont
        let originY: CGFloat

        switch alignmentPolicy {
        case .baseline:
            originY = 0
        case .center:
            originY = (font.capHeight + font.descender - size.height) / 2
        case .top:
            originY = font.capHeight - size.height
        case .bottom:
            originY = font.descender
        case let .offset(value):
            originY = value
        }

        return CGRect(origin: CGPoint(x: 0, y: originY), size: size)
    }

    func layoutSize(availableWidth: CGFloat?) -> CGSize {
        switch sizePolicy {
        case .intrinsic:
            return image?.size ?? .zero
        case let .fixed(width, height):
            return CGSize(width: width, height: height)
        case let .adaptive(maxWidth, maxHeight):
            guard let image, image.size.width > 0, image.size.height > 0 else {
                return .zero
            }

            var widthLimit = maxWidth

            if let availableWidth, availableWidth > 0 {
                widthLimit = min(widthLimit ?? availableWidth, availableWidth)
            }

            let widthScale = widthLimit.map { $0 / image.size.width } ?? 1
            let heightScale = maxHeight.map { $0 / image.size.height } ?? 1
            let scale = min(1, widthScale, heightScale)
            return CGSize(
                width: image.size.width * scale,
                height: image.size.height * scale
            )
        }
    }

    private var defaultFont: PlatformFont {
        #if canImport(UIKit)
        PlatformFont.preferredFont(forTextStyle: .body)
        #elseif canImport(AppKit)
        PlatformFont.systemFont(ofSize: PlatformFont.systemFontSize)
        #endif
    }
}
}

public extension NSAttributedString.Key {
    static let attributedAttachmentID = NSAttributedString.Key(
        "Attributed.AttachmentID"
    )
}
