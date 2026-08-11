// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import Attributed
import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct FeatureShowcaseDemoView: View {
    private let rendered = AAttributedText {
        AParagraph {
            AText("ATTRIBUTED")
                .font(.boldSystemFont(ofSize: 32))
                .foregroundColor(ShowcaseColors.blue)
                .kern(4)
            "\n"
            AText("A TextKit 2 Rich Text Showcase")
                .font(.systemFont(ofSize: 17))
                .foregroundColor(ShowcaseColors.secondary)
        }
        .alignment(.center)
        .paragraphSpacing(28)

        AParagraph {
            AText("01  STYLE INHERITANCE")
                .font(.boldSystemFont(ofSize: 13))
                .foregroundColor(ShowcaseColors.secondary)
                .kern(2)
            "\n"
            "This sentence inherits the paragraph font and semantic foreground color. "
            AText("Bold blue")
                .font(.boldSystemFont(ofSize: 19))
                .foregroundColor(ShowcaseColors.blue)
            ", "
            AText("purple underline")
                .foregroundColor(ShowcaseColors.purple)
                .underline(.single, color: ShowcaseColors.purple)
            ", and "
            AText("adaptive highlight")
                .foregroundColor(ShowcaseColors.primary)
                .backgroundColor(ShowcaseColors.highlight)
            " override only their own attributes."
        }
        .font(.systemFont(ofSize: 18))
        .foregroundColor(ShowcaseColors.primary)
        .lineSpacing(6)
        .paragraphSpacing(24)

        AParagraph {
            AText("02  BUILDERS & INLINE COMPOSITION")
                .font(.boldSystemFont(ofSize: 13))
                .foregroundColor(ShowcaseColors.secondary)
                .kern(2)
            "\n"
            "Generated tags: "

            for tag in ["Swift", "DSL", "TextKit 2", "SwiftUI"] {
                AText("  \(tag)  ")
                    .font(.boldSystemFont(ofSize: 13))
                    .foregroundColor(ShowcaseColors.badgeForeground)
                    .backgroundColor(ShowcaseColors.orange)
                " "
            }

            if true {
                "\n"
                AText("Conditional content is active")
                    .foregroundColor(ShowcaseColors.green)
                    .underline()
            }
        }
        .font(.systemFont(ofSize: 17))
        .lineSpacing(8)
        .paragraphSpacing(24)

        AParagraph {
            AText("03  TYPOGRAPHIC DETAILS")
                .font(.boldSystemFont(ofSize: 13))
                .foregroundColor(ShowcaseColors.secondary)
                .kern(2)
            "\n"
            "Chemical notation: H"
            AText("2")
                .font(.systemFont(ofSize: 12))
                .baselineOffset(-4)
            "O   Mathematical notation: x"
            AText("2")
                .font(.systemFont(ofSize: 12))
                .baselineOffset(7)
            "   Letter spacing: "
            AText("W I D E")
                .foregroundColor(ShowcaseColors.purple)
                .kern(3)
        }
        .font(.systemFont(ofSize: 20))
        .lineSpacing(6)
        .paragraphSpacing(24)

        AParagraph {
            AText("04  LINKS & INTERACTIONS")
                .font(.boldSystemFont(ofSize: 13))
                .foregroundColor(ShowcaseColors.secondary)
                .kern(2)
            "\n"
            "Standard URL: "
            ALink("example.com", url: URL(string: "https://example.com")!)
                .font(.boldSystemFont(ofSize: 17))
                .foregroundColor(ShowcaseColors.blue)
                .underline(.single, color: ShowcaseColors.blue)
            "   •   "
            ALink("registered custom action") {}
                .foregroundColor(ShowcaseColors.purple)
                .underline()
            "\n"
            AText("The custom action is registered in Core; host-side invocation is not implemented yet.")
                .font(.systemFont(ofSize: 13))
                .foregroundColor(ShowcaseColors.secondary)
        }
        .font(.systemFont(ofSize: 17))
        .backgroundColor(ShowcaseColors.highlight)
        .lineSpacing(6)
        .paragraphSpacing(24)

        AParagraph {
            AText("05  INLINE IMAGE ALIGNMENT")
                .font(.boldSystemFont(ofSize: 13))
                .foregroundColor(ShowcaseColors.secondary)
                .kern(2)
            "\n"
            "baseline "
            AImage(
                DemoImages.symbol("1.circle.fill", color: .systemBlue),
                accessibilityLabel: "Baseline image"
            )
            .size(.fixed(width: 28, height: 28))
            .alignment(.baseline)
            "   center "
            AImage(
                DemoImages.symbol("2.circle.fill", color: .systemGreen),
                accessibilityLabel: "Centered image"
            )
            .size(.fixed(width: 28, height: 28))
            .alignment(.center)
            "   top "
            AImage(
                DemoImages.symbol("3.circle.fill", color: .systemOrange),
                accessibilityLabel: "Top-aligned image"
            )
            .size(.fixed(width: 28, height: 28))
            .alignment(.top)
            "   bottom "
            AImage(
                DemoImages.symbol("4.circle.fill", color: .systemPink),
                accessibilityLabel: "Bottom-aligned image"
            )
            .size(.fixed(width: 28, height: 28))
            .alignment(.bottom)
            "   offset "
            AImage(
                DemoImages.symbol("5.circle.fill", color: .systemPurple),
                accessibilityLabel: "Offset image"
            )
            .size(.fixed(width: 28, height: 28))
            .alignment(.offset(6))
        }
        .font(.systemFont(ofSize: 18))
        .lineSpacing(10)
        .paragraphSpacing(26)

        AParagraph {
            AText("06  IMAGE SIZING")
                .font(.boldSystemFont(ofSize: 13))
                .foregroundColor(ShowcaseColors.secondary)
                .kern(2)
            "\n"
            "Intrinsic symbol  "
            AImage(
                DemoImages.symbol("photo.fill", color: .systemBlue),
                accessibilityLabel: "Intrinsic photo symbol"
            )
            .size(.intrinsic)
            .alignment(.center)
            "   Fixed banner  "
            AImage(
                DemoImages.banner,
                accessibilityLabel: "Fixed demonstration banner"
            )
            .size(.fixed(width: 96, height: 40))
            .alignment(.center)
            "\nAdaptive banner follows the available line width:\n"
            AImage(
                DemoImages.banner,
                accessibilityLabel: "Adaptive demonstration banner"
            )
            .size(.adaptive(maxWidth: 640, maxHeight: 180))
            "\nHeight-only adaptive banner:\n"
            AImage(
                DemoImages.banner,
                accessibilityLabel: "Height-constrained demonstration banner"
            )
            .size(.adaptive(maxWidth: nil, maxHeight: 64))
        }
        .font(.systemFont(ofSize: 17))
        .lineSpacing(8)
        .paragraphSpacing(28)

        AParagraph {
            AText("07  ASYNC STATES")
                .font(.boldSystemFont(ofSize: 13))
                .foregroundColor(ShowcaseColors.secondary)
                .kern(2)
            "\n"
            "No placeholder → empty loading state → resolved image:\n"
            AImage(
                source: .async {
                    try await Task.sleep(for: .milliseconds(1_400))
                    return await DemoImages.banner
                },
                accessibilityLabel: "Delayed async banner"
            )
            .size(.adaptive(maxWidth: 520, maxHeight: 150))
            "\nFailed source keeps its explicit placeholder  "
            AImage(
                source: .async {
                    try await Task.sleep(for: .milliseconds(700))
                    throw URLError(.cannotLoadFromNetwork)
                },
                placeholder: DemoImages.symbol(
                    "exclamationmark.triangle.fill",
                    color: .systemOrange
                ),
                accessibilityLabel: "Failed async image"
            )
            .size(.fixed(width: 26, height: 26))
            .alignment(.center)
        }
        .font(.systemFont(ofSize: 17))
        .lineSpacing(8)
        .paragraphSpacing(28)

        AParagraph {
            AText("08  REMOTE IMAGE")
                .font(.boldSystemFont(ofSize: 13))
                .foregroundColor(ShowcaseColors.secondary)
                .kern(2)
            "\n"
            "This request uses the provider injected at app launch. Both downloader-managed caches are disabled in the Demo.\n"
            AImage(
                remoteURL: DemoURLs.landscape,
                accessibilityLabel: "Remote showcase landscape"
            )
            .size(.adaptive(maxWidth: 640, maxHeight: 220))
        }
        .font(.systemFont(ofSize: 17))
        .lineSpacing(8)
        .paragraphSpacing(28)

        AParagraph {
            AText("09  BIDIRECTIONAL TEXT")
                .font(.boldSystemFont(ofSize: 13))
                .foregroundColor(ShowcaseColors.secondary)
                .kern(2)
            "\n"
            "English begins on the left, العربية appears inline, עברית continues naturally, and an image "
            AImage(
                DemoImages.symbol("globe", color: .systemBlue),
                accessibilityLabel: "Globe"
            )
            .size(.fixed(width: 22, height: 22))
            .alignment(.center)
            " remains part of the same mixed-direction paragraph."
        }
        .font(.systemFont(ofSize: 18))
        .lineSpacing(7)
        .paragraphSpacing(20)

        AParagraph {
            "هذا سطر مستقل من اليمين إلى اليسار مع صورة "
            AImage(
                DemoImages.symbol("arrow.left.circle.fill", color: .systemGreen),
                accessibilityLabel: "Left arrow"
            )
            .size(.fixed(width: 24, height: 24))
            .alignment(.center)
            " ونص طويل لاختبار الالتفاف والمحاذاة داخل نافذة قابلة لتغيير الحجم."
        }
        .font(.systemFont(ofSize: 18))
        .baseWritingDirection(.rightToLeft)
        .alignment(.right)
        .lineSpacing(7)
        .paragraphSpacing(28)

        AParagraph {
            AText("10  RESPONSIVE LONG FORM")
                .font(.boldSystemFont(ofSize: 13))
                .foregroundColor(ShowcaseColors.secondary)
                .kern(2)
            "\n"
            "Resize the macOS window or rotate the device. This deliberately long paragraph verifies TextKit measurement, SwiftUI proposal-based sizing, line wrapping, semantic color adaptation, selection, and inline attachment placement. "
            AImage(
                DemoImages.symbol("checkmark.seal.fill", color: .systemGreen),
                accessibilityLabel: "Verified"
            )
            .size(.fixed(width: 22, height: 22))
            .alignment(.center)
            " The final words should continue naturally after the attachment without clipping or introducing an unexpected paragraph terminator."
        }
        .font(.systemFont(ofSize: 18))
        .baseWritingDirection(.leftToRight)
        .alignment(.left)
        .lineSpacing(8)
        .paragraphSpacing(26)

        AParagraph {
            "END OF "
            AText("SHOWCASE")
                .font(.boldSystemFont(ofSize: 13))
                .foregroundColor(ShowcaseColors.secondary)
                .kern(3)
        }
        .font(.boldSystemFont(ofSize: 13))
        .foregroundColor(ShowcaseColors.secondary)
        .kern(1)
        .alignment(.center)
    }.render()

    var body: some View {
        DemoSection(
            title: "All Features",
            rendered: rendered,
            details: "One deliberately dense document covering every currently implemented DSL, layout, interaction-registration, attachment, loading, TextKit, SwiftUI sizing, direction, and appearance feature."
        )
    }
}

private enum ShowcaseColors {
    #if canImport(UIKit)
    static let primary = PlatformColor.label
    static let secondary = PlatformColor.secondaryLabel
    static let highlight = PlatformColor.tertiarySystemFill
    #elseif canImport(AppKit)
    static let primary = PlatformColor.labelColor
    static let secondary = PlatformColor.secondaryLabelColor
    static let highlight = PlatformColor.controlBackgroundColor
    #endif

    static let blue = PlatformColor.systemBlue
    static let purple = PlatformColor.systemPurple
    static let green = PlatformColor.systemGreen
    static let orange = PlatformColor.systemOrange
    static let badgeForeground = PlatformColor.white
}
