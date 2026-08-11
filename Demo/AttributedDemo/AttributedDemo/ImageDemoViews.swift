// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import Attributed
import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct ImageDemoView: View {
    private let rendered = AAttributedText {
        AParagraph {
            "Inline status "
            AImage(
                DemoImages.symbol("checkmark.circle.fill", color: .systemGreen),
                accessibilityLabel: "Online"
            )
            .size(.fixed(width: 18, height: 18))
            .alignment(.center)
            " continues on the same line."
        }
        .font(.systemFont(ofSize: 18))
        .paragraphSpacing(16)

        AParagraph {
            "Multiple "
            AImage(DemoImages.symbol("star.fill", color: .systemYellow))
                .size(.fixed(width: 20, height: 20))
                .alignment(.bottom)
            " inline "
            AImage(DemoImages.symbol("heart.fill", color: .systemPink))
                .size(.fixed(width: 24, height: 24))
                .alignment(.top)
            " alignments."
        }
        .font(.systemFont(ofSize: 18))
        .paragraphSpacing(16)

        AParagraph {
            AImage(
                DemoImages.banner,
                accessibilityLabel: "Blue demonstration banner"
            )
            .size(.adaptive(maxWidth: 640, maxHeight: 180))
        }
        .paragraphSpacing(16)

        AParagraph {
            "اتجاه من اليمين "
            AImage(DemoImages.symbol("arrow.left.circle.fill", color: .systemBlue))
                .size(.fixed(width: 22, height: 22))
                .alignment(.center)
            " مع صورة مضمّنة"
        }
        .font(.systemFont(ofSize: 18))
        .baseWritingDirection(.rightToLeft)
        .alignment(.right)
    }.render()

    var body: some View {
        DemoSection(
            title: "Image Attachments",
            rendered: rendered,
            details: "Covers fixed, adaptive, inline, multi-image, alignment, and right-to-left attachment layout."
        )
    }
}

struct ImageSizingDemoView: View {
    private let rendered = AAttributedText {
        AParagraph {
            "Intrinsic size"
        }
        .font(.boldSystemFont(ofSize: 18))
        .paragraphSpacing(8)

        AParagraph {
            AImage(DemoImages.symbol("photo.fill", color: .systemBlue))
                .size(.intrinsic)
        }
        .paragraphSpacing(20)

        AParagraph {
            "The same image forced into 32 × 32 and 96 × 40 bounds."
        }
        .font(.systemFont(ofSize: 16))
        .paragraphSpacing(8)

        AParagraph {
            AImage(DemoImages.banner)
                .size(.fixed(width: 32, height: 32))
            "  "
            AImage(DemoImages.banner)
                .size(.fixed(width: 96, height: 40))
        }
        .paragraphSpacing(20)

        AParagraph {
            "Adaptive image capped at 640 × 180. Narrow the window to verify that it follows the available line width."
        }
        .font(.systemFont(ofSize: 16))
        .paragraphSpacing(8)

        AParagraph {
            AImage(DemoImages.banner)
                .size(.adaptive(maxWidth: 640, maxHeight: 180))
        }

        AParagraph {
            "Height-only adaptive constraint:"
        }
        .font(.systemFont(ofSize: 16))
        .paragraphSpacing(8)

        AParagraph {
            AImage(DemoImages.banner)
                .size(.adaptive(maxWidth: nil, maxHeight: 64))
        }
    }.render()

    var body: some View {
        DemoSection(
            title: "Image Sizing",
            rendered: rendered,
            details: "Covers intrinsic, fixed, width-aware adaptive, and height-only adaptive sizing."
        )
    }
}

struct ImageAlignmentDemoView: View {
    private let rendered = AAttributedText {
        AParagraph {
            "Baseline "
            AImage(DemoImages.symbol("circle.fill", color: .systemBlue))
                .size(.fixed(width: 28, height: 28))
                .alignment(.baseline)
            " reference text"
        }
        .font(.systemFont(ofSize: 20))
        .lineSpacing(8)
        .paragraphSpacing(18)

        AParagraph {
            "Center   "
            AImage(DemoImages.symbol("circle.fill", color: .systemGreen))
                .size(.fixed(width: 28, height: 28))
                .alignment(.center)
            " reference text"
        }
        .font(.systemFont(ofSize: 20))
        .lineSpacing(8)
        .paragraphSpacing(18)

        AParagraph {
            "Top      "
            AImage(DemoImages.symbol("circle.fill", color: .systemOrange))
                .size(.fixed(width: 28, height: 28))
                .alignment(.top)
            " reference text"
        }
        .font(.systemFont(ofSize: 20))
        .lineSpacing(8)
        .paragraphSpacing(18)

        AParagraph {
            "Bottom "
            AImage(DemoImages.symbol("circle.fill", color: .systemPink))
                .size(.fixed(width: 28, height: 28))
                .alignment(.bottom)
            " reference text"
        }
        .font(.systemFont(ofSize: 20))
        .lineSpacing(8)
        .paragraphSpacing(18)

        AParagraph {
            "Offset  "
            AImage(DemoImages.symbol("arrow.up.circle.fill", color: .systemPurple))
                .size(.fixed(width: 28, height: 28))
                .alignment(.offset(6))
            " raised by six points"
        }
        .font(.systemFont(ofSize: 20))
        .lineSpacing(8)
        .paragraphSpacing(18)
    }
    .render()

    var body: some View {
        DemoSection(
            title: "Inline Alignment",
            rendered: rendered,
            details: "Places equal-sized attachments against the same font metrics so baseline differences remain visible."
        )
    }
}

struct ImageWrappingDemoView: View {
    private let rendered = AAttributedText {
        AParagraph {
            "A long inline sequence starts with ordinary text, then inserts "
            AImage(DemoImages.symbol("paperclip", color: .systemBlue))
                .size(.fixed(width: 20, height: 20))
                .alignment(.center)
            " an attachment before continuing across several lines. Resize the window repeatedly to verify that the image moves with its surrounding words and never becomes detached from the text run. "
            AImage(DemoImages.symbol("checkmark.seal.fill", color: .systemGreen))
                .size(.fixed(width: 24, height: 24))
                .alignment(.center)
            " The final attachment should wrap naturally near the end."
        }
        .font(.systemFont(ofSize: 18))
        .lineSpacing(6)
        .paragraphSpacing(20)

        AParagraph {
            for index in 1...12 {
                AImage(DemoImages.symbol("star.fill", color: .systemYellow))
                    .size(.fixed(width: 18, height: 18))
                    .alignment(.center)
                " item-\(index) "
            }
        }
        .font(.systemFont(ofSize: 16))
        .lineSpacing(8)
    }.render()

    var body: some View {
        DemoSection(
            title: "Wrapping & Long Text",
            rendered: rendered,
            details: "Exercises attachments at line boundaries, repeated inline nodes, builder loops, and live width changes."
        )
    }
}

struct ImageDirectionDemoView: View {
    private let rendered = AAttributedText {
        AParagraph {
            "Left-to-right before "
            AImage(DemoImages.symbol("arrow.right.circle.fill", color: .systemBlue))
                .size(.fixed(width: 24, height: 24))
                .alignment(.center)
            " after the image"
        }
        .font(.systemFont(ofSize: 18))
        .baseWritingDirection(.leftToRight)
        .alignment(.left)
        .paragraphSpacing(24)

        AParagraph {
            "نص قبل الصورة "
            AImage(DemoImages.symbol("arrow.left.circle.fill", color: .systemGreen))
                .size(.fixed(width: 24, height: 24))
                .alignment(.center)
            " ونص بعدها"
        }
        .font(.systemFont(ofSize: 18))
        .baseWritingDirection(.rightToLeft)
        .alignment(.right)
        .paragraphSpacing(24)

        AParagraph {
            "English "
            AImage(DemoImages.symbol("globe", color: .systemPurple))
                .size(.fixed(width: 22, height: 22))
                .alignment(.center)
            " العربية בתוך a mixed bidirectional paragraph."
        }
        .font(.systemFont(ofSize: 18))
    }.render()

    var body: some View {
        DemoSection(
            title: "Image Direction",
            rendered: rendered,
            details: "Compares explicit LTR, explicit RTL, and naturally resolved bidirectional text containing attachments."
        )
    }
}

struct AsyncImageStatesDemoView: View {
    private let rendered = AAttributedText {
        AParagraph {
            "Delayed async success starts with the default loading indicator and then expands to the loaded image."
        }
        .font(.systemFont(ofSize: 17))
        .paragraphSpacing(12)

        AParagraph {
            AImage(
                source: .async {
                    try await Task.sleep(for: .milliseconds(900))
                    return await DemoImages.banner
                },
                accessibilityLabel: "Delayed demonstration banner"
            )
            .size(.adaptive(maxWidth: 640, maxHeight: 260))
        }
        .paragraphSpacing(16)

        AParagraph {
            "A failed async source keeps its placeholder: "
            AImage(
                source: .async {
                    throw URLError(.cannotLoadFromNetwork)
                },
                placeholder: DemoImages.symbol(
                    "exclamationmark.triangle.fill",
                    color: .systemOrange
                ),
                accessibilityLabel: "Image failed to load"
            )
            .size(.fixed(width: 24, height: 24))
            .alignment(.center)
        }
        .font(.systemFont(ofSize: 17))
    }.render()

    var body: some View {
        DemoSection(
            title: "Async Image States",
            rendered: rendered,
            details: "The successful source verifies the default loading indicator plus content and layout updates. The failed source verifies that an explicit placeholder remains stable."
        )
    }
}

struct RemoteImageDemoView: View {
    private let rendered = AAttributedText {
        AParagraph {
            "A remote image with a 320 × 160 placeholder:"
        }
        .font(.systemFont(ofSize: 17))
        .paragraphSpacing(12)

        AParagraph {
            AImage(
                remoteURL: DemoURLs.landscape,
                placeholder: DemoImages.placeholder,
                accessibilityLabel: "Remote landscape sample"
            )
            .size(.adaptive(maxWidth: 640, maxHeight: 260))
        }
        .paragraphSpacing(18)

        AParagraph {
            "A remote image without a placeholder initially occupies no attachment space and must trigger layout after loading:"
        }
        .font(.systemFont(ofSize: 17))
        .paragraphSpacing(12)

        AParagraph {
            AImage(
                remoteURL: DemoURLs.square,
                accessibilityLabel: "Remote square sample"
            )
            .size(.adaptive(maxWidth: 320, maxHeight: 240))
        }
    }.render()

    var body: some View {
        DemoSection(
            title: "Remote Images",
            rendered: rendered,
            details: "Uses the provider installed at app launch with disk caching disabled. It compares placeholder and no-placeholder layout paths."
        )
    }
}

struct RemoteImageGalleryDemoView: View {
    private let rendered = AAttributedText {
        AParagraph {
            "Several remote attachments load independently. Their different source aspect ratios should remain intact."
        }
        .font(.systemFont(ofSize: 17))
        .paragraphSpacing(16)

        for item in DemoURLs.gallery {
            AParagraph {
                AText(item.title)
                    .font(.boldSystemFont(ofSize: 16))
                "\n"
                AImage(
                    remoteURL: item.url,
                    placeholder: DemoImages.placeholder,
                    accessibilityLabel: item.title
                )
                .size(.adaptive(maxWidth: 520, maxHeight: 220))
            }
            .paragraphSpacing(20)
        }
    }.render()

    var body: some View {
        DemoSection(
            title: "Remote Gallery",
            rendered: rendered,
            details: "Covers multiple concurrent requests, repeated attachment updates, differing aspect ratios, and scrolling while loading."
        )
    }
}

private enum DemoURLs {
    static let landscape = URL(
        string: "https://picsum.photos/seed/attributed-landscape/800/400"
    )!
    static let square = URL(
        string: "https://picsum.photos/seed/attributed-square/500/500"
    )!
    static let gallery: [(title: String, url: URL)] = [
        ("Wide landscape", URL(string: "https://picsum.photos/seed/attributed-wide/900/360")!),
        ("Portrait", URL(string: "https://picsum.photos/seed/attributed-portrait/420/700")!),
        ("Square", URL(string: "https://picsum.photos/seed/attributed-gallery-square/600/600")!),
        ("Second landscape", URL(string: "https://picsum.photos/seed/attributed-second/720/420")!)
    ]
}

private enum DemoImages {
    #if canImport(UIKit)
    static let placeholder = UIGraphicsImageRenderer(
        size: CGSize(width: 320, height: 160)
    ).image { context in
        UIColor.secondarySystemBackground.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 320, height: 160))
    }

    static let banner = UIGraphicsImageRenderer(
        size: CGSize(width: 640, height: 180)
    ).image { context in
        UIColor.systemBlue.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 640, height: 180))
        UIColor.systemTeal.setFill()
        context.fill(CGRect(x: 320, y: 0, width: 320, height: 180))
    }

    static func symbol(_ name: String, color: UIColor) -> PlatformImage {
        let configuration = UIImage.SymbolConfiguration(
            pointSize: 24,
            weight: .medium
        )
        return UIImage(systemName: name, withConfiguration: configuration)!
            .withTintColor(color, renderingMode: .alwaysOriginal)
    }
    #elseif canImport(AppKit)
    static let placeholder = NSImage(
        size: CGSize(width: 320, height: 160),
        flipped: false
    ) { bounds in
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(rect: bounds).fill()
        return true
    }

    static let banner = NSImage(
        size: CGSize(width: 640, height: 180),
        flipped: false
    ) { bounds in
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: bounds).fill()
        NSColor.systemTeal.setFill()
        NSBezierPath(
            rect: CGRect(x: 320, y: 0, width: 320, height: 180)
        ).fill()
        return true
    }

    static func symbol(_ name: String, color: NSColor) -> PlatformImage {
        let image = NSImage(
            systemSymbolName: name,
            accessibilityDescription: nil
        )!
        let configuration = NSImage.SymbolConfiguration(
            pointSize: 24,
            weight: .medium
        )
        _ = color
        return image.withSymbolConfiguration(configuration) ?? image
    }
    #endif
}
