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
            requiresLoading: requiresLoading,
            showsLoadingIndicator: requiresLoading && initialImage == nil
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
    let showsLoadingIndicator: Bool
    private let viewProviders = NSHashTable<ImageAttachmentViewProvider>.weakObjects()

    init(
        id: AttachmentID,
        source: ImageSource,
        image: PlatformImage?,
        sizePolicy: AttachmentSize,
        alignmentPolicy: AttachmentAlignment,
        accessibilityLabel: String?,
        requiresLoading: Bool,
        showsLoadingIndicator: Bool
    ) {
        self.id = id
        self.source = source
        self.sizePolicy = sizePolicy
        self.alignmentPolicy = alignmentPolicy
        imageAccessibilityLabel = accessibilityLabel
        self.requiresLoading = requiresLoading
        self.showsLoadingIndicator = showsLoadingIndicator
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
        showsLoadingIndicator
    }

    #if canImport(UIKit)
    override func viewProvider(
        for parentView: UIView?,
        location: any NSTextLocation,
        textContainer: NSTextContainer?
    ) -> NSTextAttachmentViewProvider? {
        makeViewProvider(
            parentView: parentView,
            location: location,
            textContainer: textContainer
        )
    }
    #elseif canImport(AppKit)
    override func viewProvider(
        for parentView: NSView?,
        location: any NSTextLocation,
        textContainer: NSTextContainer?
    ) -> NSTextAttachmentViewProvider? {
        makeViewProvider(
            parentView: parentView,
            location: location,
            textContainer: textContainer
        )
    }
    #endif

    func resolve(with image: PlatformImage) {
        self.image = image
        viewProviders.allObjects.forEach {
            $0.display(image: image, accessibilityLabel: imageAccessibilityLabel)
        }
    }

    func finishLoading() {
        viewProviders.allObjects.forEach { $0.stopLoading() }
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
            return image?.size ?? loadingIndicatorSize
        case let .fixed(width, height):
            return CGSize(width: width, height: height)
        case let .adaptive(maxWidth, maxHeight):
            guard let image, image.size.width > 0, image.size.height > 0 else {
                return constrainedLoadingIndicatorSize(
                    maxWidth: maxWidth,
                    maxHeight: maxHeight
                )
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

    private var loadingIndicatorSize: CGSize {
        showsLoadingIndicator ? CGSize(width: 24, height: 24) : .zero
    }

    private func constrainedLoadingIndicatorSize(
        maxWidth: CGFloat?,
        maxHeight: CGFloat?
    ) -> CGSize {
        guard showsLoadingIndicator else {
            return .zero
        }

        return CGSize(
            width: min(24, maxWidth ?? 24),
            height: min(24, maxHeight ?? 24)
        )
    }

    #if canImport(UIKit)
    private func makeViewProvider(
        parentView: UIView?,
        location: any NSTextLocation,
        textContainer: NSTextContainer?
    ) -> NSTextAttachmentViewProvider {
        let provider = ImageAttachmentViewProvider(
            textAttachment: self,
            parentView: parentView,
            textLayoutManager: textContainer?.textLayoutManager,
            location: location
        )
        viewProviders.add(provider)
        return provider
    }
    #elseif canImport(AppKit)
    private func makeViewProvider(
        parentView: NSView?,
        location: any NSTextLocation,
        textContainer: NSTextContainer?
    ) -> NSTextAttachmentViewProvider {
        let provider = ImageAttachmentViewProvider(
            textAttachment: self,
            parentView: parentView,
            textLayoutManager: textContainer?.textLayoutManager,
            location: location
        )
        viewProviders.add(provider)
        return provider
    }
    #endif

    private var defaultFont: PlatformFont {
        #if canImport(UIKit)
        PlatformFont.preferredFont(forTextStyle: .body)
        #elseif canImport(AppKit)
        PlatformFont.systemFont(ofSize: PlatformFont.systemFontSize)
        #endif
    }
}
}

#if canImport(UIKit)
private final class ImageAttachmentViewProvider: NSTextAttachmentViewProvider {
    override func loadView() {
        let attachmentView = ImageAttachmentView()
        if let attachment = textAttachment as? Attributed.ImageTextAttachment,
           let image = attachment.image {
            attachmentView.display(
                image: image,
                accessibilityLabel: attachment.imageAccessibilityLabel
            )
        }
        view = attachmentView
    }

    func display(image: PlatformImage, accessibilityLabel: String?) {
        (view as? ImageAttachmentView)?.display(
            image: image,
            accessibilityLabel: accessibilityLabel
        )
    }

    func stopLoading() {
        (view as? ImageAttachmentView)?.stopLoading()
    }
}

private final class ImageAttachmentView: UIView {
    private let imageView = UIImageView()
    private let indicator = UIActivityIndicatorView(style: .medium)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        imageView.contentMode = .scaleAspectFit
        imageView.isHidden = true
        addSubview(imageView)
        addSubview(indicator)
        indicator.startAnimating()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        indicator.center = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    func display(image: UIImage, accessibilityLabel: String?) {
        indicator.stopAnimating()
        imageView.image = image
        imageView.isHidden = false
        isAccessibilityElement = accessibilityLabel != nil
        self.accessibilityLabel = accessibilityLabel
    }

    func stopLoading() {
        indicator.stopAnimating()
    }
}
#elseif canImport(AppKit)
private final class ImageAttachmentViewProvider: NSTextAttachmentViewProvider {
    override func loadView() {
        let attachmentView = ImageAttachmentView()
        if let attachment = textAttachment as? Attributed.ImageTextAttachment,
           let image = attachment.image {
            attachmentView.display(
                image: image,
                accessibilityLabel: attachment.imageAccessibilityLabel
            )
        }
        view = attachmentView
    }

    func display(image: PlatformImage, accessibilityLabel: String?) {
        (view as? ImageAttachmentView)?.display(
            image: image,
            accessibilityLabel: accessibilityLabel
        )
    }

    func stopLoading() {
        (view as? ImageAttachmentView)?.stopLoading()
    }
}

private final class ImageAttachmentView: NSView {
    private let imageView = NSImageView()
    private let indicator = NSProgressIndicator()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.isHidden = true
        indicator.style = .spinning
        indicator.controlSize = .small
        indicator.isDisplayedWhenStopped = false
        indicator.sizeToFit()
        addSubview(imageView)
        addSubview(indicator)
        indicator.startAnimation(nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func layout() {
        super.layout()
        imageView.frame = bounds
        indicator.frame.origin = CGPoint(
            x: bounds.midX - indicator.frame.width / 2,
            y: bounds.midY - indicator.frame.height / 2
        )
    }

    func display(image: NSImage, accessibilityLabel: String?) {
        indicator.stopAnimation(nil)
        imageView.image = image
        imageView.isHidden = false
        setAccessibilityElement(accessibilityLabel != nil)
        setAccessibilityLabel(accessibilityLabel)
    }

    func stopLoading() {
        indicator.stopAnimation(nil)
    }
}
#endif

public extension NSAttributedString.Key {
    static let attributedAttachmentID = NSAttributedString.Key(
        "Attributed.AttachmentID"
    )
}
