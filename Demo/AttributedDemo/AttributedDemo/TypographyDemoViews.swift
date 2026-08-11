// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import Attributed
import Foundation
import SwiftUI

struct LongTextDemoView: View {
    private let paragraphs = [
        "Attributed is a small DSL for constructing rich text while keeping style inheritance explicit. This page deliberately contains enough content to exercise wrapping, scrolling, selection, and paragraph boundaries.",
        "长文本不仅要验证字符串是否正确，还要观察换行、段落间距、字体继承，以及容器宽度改变后的重新排版。调整窗口宽度时，这一段应该自然重排。",
        "Inline content can mix plain strings with strongly typed nodes. A paragraph provides defaults, while individual nodes override only the values they own.",
        "العربية تُستخدم هنا لاختبار تشكيل الحروف والالتفاف داخل نص طويل، بينما توجد صفحة مستقلة لاختبار اتجاه الكتابة من اليمين إلى اليسار.",
        "עברית מופיעה גם היא כדי לוודא שטקסט דו־כיווני נשמר ואינו משנה את סדר הפסקאות האחרות.",
        "The final paragraph makes it easy to verify that rendering removes only the document's final paragraph terminator and does not collapse preceding paragraph boundaries."
    ]

    private var rendered: ARenderedAttributedText {
        AAttributedText {
            for paragraph in paragraphs {
                AParagraph {
                    paragraph
                }
                .font(.systemFont(ofSize: 17))
                .lineSpacing(6)
                .paragraphSpacing(14)
            }
        }.render()
    }

    var body: some View {
        DemoSection(
            title: "Long Text",
            rendered: rendered,
            details: "Resize the window or rotate the device to inspect wrapping and paragraph stability."
        )
    }
}

struct MixedStylesDemoView: View {
    private let rendered = AAttributedText {
        AParagraph {
            AText("Large Bold")
                .font(.boldSystemFont(ofSize: 28))
                .foregroundColor(.blue)
            "  "
            AText("small secondary")
                .font(.systemFont(ofSize: 13))
                .foregroundColor(.gray)
        }
        .paragraphSpacing(14)

        AParagraph {
            AText("Highlighted")
                .foregroundColor(.black)
                .backgroundColor(.yellow)
            "  "
            AText("underlined")
                .foregroundColor(.purple)
                .underline(.single, color: .purple)
            "  "
            AText("spaced")
                .kern(3)
        }
        .font(.systemFont(ofSize: 18))
        .paragraphSpacing(14)

        AParagraph {
            "H"
            AText("2").font(.systemFont(ofSize: 12)).baselineOffset(-4)
            "O and x"
            AText("2").font(.systemFont(ofSize: 12)).baselineOffset(7)
        }
        .font(.systemFont(ofSize: 22))
    }.render()

    var body: some View {
        DemoSection(
            title: "Mixed Styles",
            rendered: rendered,
            details: "Exercises font, color, background, underline, kern, and baseline offset overrides in the same document."
        )
    }
}

struct InlineCompositionDemoView: View {
    private let tags = ["Swift", "DSL", "NSAttributedString"]
    private let showsBadge = true

    private var rendered: ARenderedAttributedText {
        AAttributedText {
            AParagraph {
                "Result builder: "

                if showsBadge {
                    AText("ACTIVE")
                        .font(.boldSystemFont(ofSize: 12))
                        .foregroundColor(.white)
                        .backgroundColor(.green)
                }

                "\nTags: "

                for tag in tags {
                    AText("[\(tag)] ")
                        .foregroundColor(.orange)
                }

                "\nRead "
                ALink("the example", url: URL(string: "https://example.com")!)
                    .foregroundColor(.blue)
                    .underline()
                "."
            }
            .font(.systemFont(ofSize: 17))
            .lineSpacing(5)
        }.render()
    }

    var body: some View {
        DemoSection(
            title: "Inline Composition",
            rendered: rendered,
            details: "Mixes raw strings, conditional nodes, loops, styled text, explicit newlines, and a link inside one paragraph."
        )
    }
}

struct ParagraphDemoView: View {
    private let rendered = AAttributedText {
        AParagraph {
            "Leading paragraph with increased line and paragraph spacing. The extra sentence makes alignment and wrapping easier to inspect."
        }
        .font(.systemFont(ofSize: 18))
        .lineSpacing(8)
        .paragraphSpacing(18)

        AParagraph {
            "Centered paragraph"
        }
        .font(.boldSystemFont(ofSize: 18))
        .alignment(.center)
        .paragraphSpacing(18)

        AParagraph {
            "Trailing paragraph"
        }
        .font(.systemFont(ofSize: 18))
        .alignment(.right)
    }.render()

    var body: some View {
        DemoSection(
            title: "Paragraph Layout",
            rendered: rendered,
            details: "Compares leading, centered, and trailing paragraph alignment with independent spacing."
        )
    }
}

struct LinkDemoView: View {
    private let rendered = AAttributedText {
        AParagraph {
            "Visit "
            ALink("example.com", url: URL(string: "https://example.com")!)
                .foregroundColor(.blue)
                .underline()
            " to verify the standard URL attribute."
        }
        .font(.systemFont(ofSize: 18))
    }.render()

    var body: some View {
        DemoSection(
            title: "Links",
            rendered: rendered,
            details: "URL links contain both the standard link attribute and Attributed's interaction ID. Custom actions need the future host adapter."
        )
    }
}
