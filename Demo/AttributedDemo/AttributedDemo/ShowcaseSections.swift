// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import Attributed
import UIKit

@MainActor
protocol ShowcaseActions: AnyObject {
    func show(_ message: String)
}

struct ShowcaseSample {
    var caption: String?
    var text: ATRAttributedText
    var configure: (ATRTextView) -> Void = { _ in }
}

struct ShowcaseSection {
    let title: String
    let samples: [ShowcaseSample]
}

// Each section exercises one feature area; the last ones mix them. Long text
// rendering lives in its own page, not here.
@MainActor
enum ShowcaseSections {
    static let body = UIFont.systemFont(ofSize: 17)
    static let sunset = ATRTextGradient(colors: [.systemPink, .systemOrange])
    static let ocean = ATRTextGradient(colors: [.systemBlue, .systemTeal, .systemGreen])

    static func all(actions: ShowcaseActions) -> [ShowcaseSection] {
        [
            typography,
            paragraphs,
            underlines,
            gradients,
            images,
            interactions(actions: actions),
            mixedContent,
            scripts,
            truncation,
            kitchenSink,
        ]
    }

    static var typography: ShowcaseSection {
        let rounded = UIFont.systemFont(ofSize: 20, weight: .bold).fontDescriptor
            .withDesign(.rounded)
            .map { UIFont(descriptor: $0, size: 20) } ?? .systemFont(ofSize: 20)
        let small = UIFont.systemFont(ofSize: 11)

        return ShowcaseSection(title: "Typography", samples: [
            ShowcaseSample(caption: "Fonts", text: ATRAttributedText {
                ATRParagraph {
                    ATRText("Bold ").font(.systemFont(ofSize: 20, weight: .bold))
                    ATRText("Italic ").font(.italicSystemFont(ofSize: 20))
                    ATRText("Mono ").font(.monospacedSystemFont(ofSize: 18, weight: .regular))
                    ATRText("Rounded ").font(rounded)
                    ATRText("Serif").font(UIFont(name: "Georgia", size: 20) ?? body)
                }
            }),
            ShowcaseSample(caption: "Color, background, kerning, baseline offset", text: ATRAttributedText {
                ATRParagraph {
                    ATRText("Colored").foregroundColor(.systemPink)
                    ", "
                    ATRText(" highlighted ").backgroundColor(.systemYellow.withAlphaComponent(0.45))
                    ", "
                    ATRText("TRACKED").kern(5)
                    ", E = mc"
                    ATRText("2").font(small).baselineOffset(7)
                    " and H"
                    ATRText("2").font(small).baselineOffset(-3)
                    "O."
                }
                .font(body)
            }),
        ])
    }

    static var paragraphs: ShowcaseSection {
        let sentence = "Paragraph styles control alignment, line spacing, and the space between paragraphs."

        return ShowcaseSection(title: "Paragraphs", samples: [
            ShowcaseSample(caption: "Left, center, right, justified", text: ATRAttributedText {
                ATRParagraph { "Left aligned" }.alignment(.left)
                ATRParagraph { "Centered" }.alignment(.center)
                ATRParagraph { "Right aligned" }.alignment(.right)
                ATRParagraph { sentence }.alignment(.justified)
            }),
            ShowcaseSample(caption: "Line spacing 8, paragraph spacing 16", text: ATRAttributedText {
                ATRParagraph { sentence }.lineSpacing(8).paragraphSpacing(16)
                ATRParagraph { "A second paragraph follows the spacing." }
            }),
            ShowcaseSample(caption: "Natural direction follows the first strong character", text: ATRAttributedText {
                ATRParagraph { "مرحبا بالعالم، هذا نص عربي." }
                ATRParagraph { "שלום עולם, זה טקסט בעברית." }
                ATRParagraph { "Mixed: English then עברית then English." }
            }),
        ])
    }

    static var underlines: ShowcaseSection {
        ShowcaseSection(title: "Underline decorations", samples: [
            ShowcaseSample(caption: "Engine-drawn: lines, patterns, thickness, corners", text: ATRAttributedText {
                ATRParagraph {
                    ATRText("Single").underline()
                    "   "
                    ATRText("Double").underline(.double, color: .systemRed)
                    "   "
                    ATRText("Dotted").underline(ATRUnderlineStyle(pattern: .dot, thickness: 3, corners: .capsule))
                }
                .font(body)
                .paragraphSpacing(10)
                ATRParagraph {
                    ATRText("Dashed").underline(ATRUnderlineStyle(pattern: .dash, thickness: 2, corners: .radius(1)), color: .systemBlue)
                    "   "
                    ATRText("Dash dot").underline(ATRUnderlineStyle(pattern: .dashDot, thickness: 2), color: .systemPurple)
                    "   "
                    ATRText("Capsule").underline(ATRUnderlineStyle(thickness: 5, corners: .capsule), color: .systemGreen)
                }
                .font(body)
            }),
            ShowcaseSample(caption: "Gradient underlines; an unfilled underline follows the text's gradient", text: ATRAttributedText {
                ATRParagraph {
                    ATRText("Gradient underline").underline(ATRUnderlineStyle(thickness: 4, corners: .capsule), gradient: sunset)
                    "   "
                    ATRText("Follows the text").gradient(ocean).underline(ATRUnderlineStyle(thickness: 3, corners: .capsule))
                }
                .font(.systemFont(ofSize: 19, weight: .semibold))
            }),
        ])
    }

    static var gradients: ShowcaseSection {
        let big = UIFont.systemFont(ofSize: 30, weight: .heavy)
        let lineGradient = ATRTextGradient(colors: [.systemPurple, .systemPink], scope: .line)
        let documentGradient = ATRTextGradient(colors: [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue], scope: .document)
        let vertical = ATRTextGradient(colors: [.systemYellow, .systemRed], startPoint: .top, endPoint: .bottom)
        let emojiText = ATRAttributedText {
            ATRParagraph {
                ATRText("Party 🎉 time 🌈 now").gradient(sunset)
            }
            .font(.systemFont(ofSize: 26, weight: .bold))
        }

        return ShowcaseSection(title: "Gradients", samples: [
            ShowcaseSample(caption: "Paragraph scope: equal gradients join across a gap", text: ATRAttributedText {
                ATRParagraph {
                    ATRText("Warm").gradient(sunset)
                    ATRText(" plain ").foregroundColor(.secondaryLabel)
                    ATRText("glow").gradient(sunset)
                }
                .font(big)
            }),
            ShowcaseSample(caption: "Line scope: the gradient restarts on every line", text: ATRAttributedText {
                ATRParagraph {
                    ATRText("Each wrapped line gets its own complete gradient from purple to pink.").gradient(lineGradient)
                }
                .font(.systemFont(ofSize: 22, weight: .bold))
            }),
            ShowcaseSample(caption: "Document scope: one gradient across paragraphs", text: ATRAttributedText {
                ATRParagraph { ATRText("First paragraph").gradient(documentGradient) }
                ATRParagraph { ATRText("Second paragraph").gradient(documentGradient) }
                ATRParagraph { ATRText("Third paragraph").gradient(documentGradient) }
            }),
            ShowcaseSample(caption: "Vertical gradient", text: ATRAttributedText {
                ATRParagraph { ATRText("Sunrise").gradient(vertical) }.font(.systemFont(ofSize: 44, weight: .black))
            }),
            ShowcaseSample(caption: "Emoji keep their colors by default", text: emojiText),
            ShowcaseSample(caption: "…or join the gradient when the view opts in", text: emojiText, configure: { textView in
                textView.appliesGradientToEmoji = true
            }),
        ])
    }

    static var images: ShowcaseSection {
        let star = DemoImages.symbol("star.fill", color: .systemYellow)
        let swatch = DemoImages.swatch(.systemTeal)

        return ShowcaseSection(title: "Images", samples: [
            ShowcaseSample(caption: "Inline images with alignment", text: ATRAttributedText {
                ATRParagraph {
                    "Baseline "
                    ATRImage(.resolved(star), size: .fixed(width: 20, height: 20))
                    "  center "
                    ATRImage(.resolved(swatch), size: .fixed(width: 18, height: 18)).alignment(.center)
                    "  top "
                    ATRImage(.resolved(swatch), size: .fixed(width: 10, height: 10)).alignment(.top)
                    "  bottom "
                    ATRImage(.resolved(swatch), size: .fixed(width: 10, height: 10)).alignment(.bottom)
                }
                .font(body)
            }),
            ShowcaseSample(caption: "Adaptive: keeps the aspect ratio and fits the line", text: ATRAttributedText {
                ATRParagraph {
                    ATRImage(.resolved(DemoImages.landscape()), size: .adaptive(maxWidth: 1000), accessibilityLabel: "Landscape")
                }
            }),
            ShowcaseSample(caption: "AsyncImage: loaded after the first render, then relaid out", text: ATRAttributedText {
                ATRParagraph {
                    "Loaded later: "
                    ATRImage(.defer { DemoImages.landscape(size: CGSize(width: 240, height: 120)) }, size: .adaptive(maxWidth: 120))
                    " and fixed "
                    ATRImage(.defer { DemoImages.symbol("bolt.fill", color: .systemOrange) }, size: .fixed(width: 20, height: 20))
                        .alignment(.center)
                }
                .font(body)
            }),
        ])
    }

    static func interactions(actions: ShowcaseActions) -> ShowcaseSection {
        let link = URL(string: "https://github.com/weirui-kong/Attributed")!
        var taps = 0

        return ShowcaseSection(title: "Interactions", samples: [
            ShowcaseSample(caption: "Every interaction reaches the delegate with its value, range, and text", text: ATRAttributedText {
                ATRParagraph {
                    "Open the "
                    ATRText("repository").link(link).foregroundColor(.link).underline()
                    ", "
                    ATRText("double-tap me").foregroundColor(.systemPurple).onTap(count: 2, value: "double tap")
                    ", "
                    ATRText("long-press me").foregroundColor(.systemOrange).onLongPress(minimumDuration: 0.5, value: 42)
                    ", or "
                    ATRText("tap to count").foregroundColor(.systemGreen).onTap { [weak actions] in
                        taps += 1
                        actions?.show("Closure ran \(taps) time(s)")
                    }
                    "."
                }
                .font(body)
                .lineSpacing(6)
            }),
            ShowcaseSample(caption: "Nested: a single tap inside a double tap; tappable image", text: ATRAttributedText {
                ATRParagraph {
                    ATRText("Double-tap the phrase, or single-tap ")
                    ATRText("this word").underline(ATRUnderlineStyle(pattern: .dot, thickness: 2, corners: .capsule)).onTap(value: "inner single tap")
                    ATRText(" inside it. ")
                    ATRImage(.resolved(DemoImages.symbol("hand.tap.fill", color: .systemBlue)), size: .fixed(width: 22, height: 22))
                        .alignment(.center)
                        .onTap(value: "image")
                }
                .font(body)
                .onTap(count: 2, value: "outer double tap")
            }),
            ShowcaseSample(caption: "Group: several styled nodes share one gesture", text: ATRAttributedText {
                ATRParagraph {
                    "Tap "
                    ATRGroup {
                        ATRText("any ").font(.systemFont(ofSize: 17, weight: .bold))
                        ATRText("of these ").foregroundColor(.systemPink)
                        ATRText("words").gradient(ocean)
                    }
                    .onTap(value: "group")
                    " for one event."
                }
                .font(body)
            }),
            ShowcaseSample(caption: "A whole paragraph can be interactive", text: ATRAttributedText {
                ATRParagraph {
                    ATRText("Tap anywhere on this text.").foregroundColor(.secondaryLabel)
                }
                .font(body)
                .onTap(value: "paragraph")
            }),
        ])
    }

    static var mixedContent: ShowcaseSection {
        let heart = DemoImages.symbol("heart.fill", color: .systemRed, pointSize: 16)

        return ShowcaseSection(title: "Mixed content", samples: [
            ShowcaseSample(caption: "文字混排：中文、English、emoji、图片、渐变与下划线", text: ATRAttributedText {
                ATRParagraph {
                    ATRText("Attributed").font(.systemFont(ofSize: 18, weight: .bold)).gradient(ocean)
                    " 支持中文、English、emoji 🎉 与图片 "
                    ATRImage(.resolved(heart), size: .fixed(width: 16, height: 16)).alignment(.center)
                    " 混排，也能给"
                    ATRText("渐变文字").gradient(sunset).underline(ATRUnderlineStyle(thickness: 3, corners: .capsule))
                    "加上下划线，或者插入"
                    ATRText("链接").link(URL(string: "https://www.apple.com")!).foregroundColor(.link).underline()
                    "。"
                }
                .font(body)
                .lineSpacing(6)
            }),
            ShowcaseSample(caption: "Several styles in one paragraph", text: ATRAttributedText {
                ATRParagraph {
                    ATRText("NEW").font(.systemFont(ofSize: 11, weight: .heavy)).foregroundColor(.white).backgroundColor(.systemRed).kern(1)
                    " "
                    ATRText("Release notes").font(.systemFont(ofSize: 19, weight: .semibold))
                    ATRText(" v2.0").font(.monospacedSystemFont(ofSize: 13, weight: .regular)).foregroundColor(.secondaryLabel).baselineOffset(4)
                }
                ATRParagraph {
                    "• Layout on CoreText, safe off the main thread"
                }
                .font(.systemFont(ofSize: 15))
                ATRParagraph {
                    "• "
                    ATRText("Gradients").gradient(sunset)
                    ", "
                    ATRText("decorations").underline(ATRUnderlineStyle(pattern: .dash, thickness: 2, corners: .capsule), color: .systemTeal)
                    ", and "
                    ATRText("gestures").foregroundColor(.systemPurple).onTap(value: "gestures")
                }
                .font(.systemFont(ofSize: 15))
            }),
        ])
    }

    static var scripts: ShowcaseSection {
        let tall = ATRAttributedText {
            ATRParagraph {
                ATRText("ကျွန်ုပ်တို့ ").backgroundColor(.systemTeal.withAlphaComponent(0.25))
                ATRText("ภาษาไทย ปั้ม").backgroundColor(.systemPink.withAlphaComponent(0.2))
            }
            .font(body)
            ATRParagraph {
                ATRText("Next line").backgroundColor(.systemYellow.withAlphaComponent(0.3))
            }
            .font(body)
        }

        return ShowcaseSection(title: "Tall scripts", samples: [
            ShowcaseSample(caption: "Typographic height: Myanmar and Thai marks overflow the line", text: tall),
            ShowcaseSample(caption: "Glyph-bounds height: the line grows to fit every glyph", text: tall, configure: { textView in
                textView.lineHeightMode = .glyphBounds
            }),
        ])
    }

    static var truncation: ShowcaseSection {
        let text = ATRAttributedText {
            ATRParagraph {
                "Long descriptions can be limited to a number of lines, with the cut marked by a truncation token at the end of the last visible line."
            }
            .font(body)
        }

        return ShowcaseSection(title: "Truncation", samples: [
            ShowcaseSample(caption: "Two lines, default token", text: text, configure: { textView in
                textView.maximumNumberOfLines = 2
            }),
            ShowcaseSample(caption: "One line, custom token", text: text, configure: { textView in
                textView.maximumNumberOfLines = 1
                textView.truncationToken = " … more"
            }),
        ])
    }

    static var kitchenSink: ShowcaseSection {
        let title = UIFont.systemFont(ofSize: 26, weight: .black)
        let serif = UIFont(name: "Georgia", size: 17) ?? body
        let serifItalic = UIFont(name: "Georgia-Italic", size: 17) ?? .italicSystemFont(ofSize: 17)
        let mono = UIFont.monospacedSystemFont(ofSize: 15, weight: .medium)
        let tiny = UIFont.systemFont(ofSize: 11, weight: .semibold)
        let aurora = ATRTextGradient(
            colors: [.systemPurple, .systemBlue, .systemTeal, .systemGreen],
            locations: [0, 0.35, 0.7, 1],
            startPoint: .topLeft,
            endPoint: .bottomRight
        )
        let ember = ATRTextGradient(colors: [.systemRed, .systemOrange, .systemYellow], scope: .line)
        let paper = ATRTextGradient(colors: [.systemIndigo, .systemPink], scope: .document)
        let star = DemoImages.symbol("star.fill", color: .systemYellow, pointSize: 14)
        let globe = DemoImages.symbol("globe.asia.australia.fill", color: .systemBlue, pointSize: 16)
        let bolt = DemoImages.symbol("bolt.fill", color: .systemOrange, pointSize: 14)
        let leaf = DemoImages.symbol("leaf.fill", color: .systemGreen, pointSize: 14)
        let wiki = URL(string: "https://en.wikipedia.org/wiki/Typography")!

        let text = ATRAttributedText {
            ATRParagraph {
                ATRText("The Atlas of ").font(title)
                ATRText("Living Type").font(title).gradient(aurora)
                ATRText("  vol. 3").font(tiny).foregroundColor(.secondaryLabel).baselineOffset(14).kern(2)
            }
            .alignment(.center)
            .paragraphSpacing(4)

            ATRParagraph {
                ATRImage(.resolved(globe), size: .fixed(width: 16, height: 16)).alignment(.center)
                ATRText("  A field guide to scripts, styles, and the space between them  ").foregroundColor(.secondaryLabel)
                ATRImage(.resolved(globe), size: .fixed(width: 16, height: 16)).alignment(.center)
            }
            .font(.systemFont(ofSize: 13, weight: .medium))
            .alignment(.center)
            .paragraphSpacing(18)

            ATRParagraph {
                ATRText("I").font(UIFont(name: "Georgia-Bold", size: 34) ?? title).gradient(ember)
                ATRText("n the beginning there was the ").font(serif)
                ATRText("glyph").font(serifItalic).underline(ATRUnderlineStyle(pattern: .dot, thickness: 2, corners: .capsule), color: .systemTeal)
                ATRText(", and the glyph was set in ").font(serif)
                ATRText("lead").font(mono).backgroundColor(.systemGray5).kern(1)
                ATRText(". Then came ").font(serif)
                ATRGroup {
                    ATRText("photo").font(serifItalic)
                    ATRText("type").font(UIFont(name: "Georgia-Bold", size: 17) ?? serif).foregroundColor(.systemIndigo)
                    ATRText("setting").font(serifItalic).underline(.double, color: .systemIndigo)
                }
                .onLongPress(minimumDuration: 0.4, value: "phototypesetting")
                ATRText(", then ").font(serif)
                ATRText("PostScript").font(mono).foregroundColor(.systemRed)
                ATRText(" ").font(serif)
                ATRImage(.resolved(bolt), size: .fixed(width: 14, height: 14)).alignment(.center)
                ATRText(" and at last the screen, where every curve became a hint of light: ").font(serif)
                ATRText("ﬁ ﬂ ﬀ — “quotes” — ½ ¾ — x²+y²=z²").font(serif).foregroundColor(.secondaryLabel)
                ATRText(". Read more on ").font(serif)
                ATRText("Wikipedia").font(serif).foregroundColor(.link).underline(ATRUnderlineStyle(thickness: 1.5, corners: .capsule)).link(wiki)
                ATRText(".").font(serif)
            }
            .alignment(.justified)
            .lineSpacing(5)
            .paragraphSpacing(14)

            ATRParagraph {
                ATRText("多语言  ").font(.systemFont(ofSize: 15, weight: .heavy)).gradient(paper)
                "中文排版讲究「标点挤压」与“避头尾”，日本語は縦書きも横書きも美しく、한국어는 띄어쓰기를 씁니다。"
                "Русский текст, Ελληνικά γράμματα, हिन्दी देवनागरी, ภาษาไทยไม่มีการเว้นวรรค, ကျွန်ုပ်တို့၏ မြန်မာစာ。"
            }
            .font(.systemFont(ofSize: 16))
            .lineSpacing(6)
            .paragraphSpacing(14)

            ATRParagraph {
                "العربية تُكتب من اليمين إلى اليسار، مع "
                ATRText("English").foregroundColor(.systemBlue).underline()
                " و "
                ATRText("123").font(mono).foregroundColor(.systemOrange)
                " في وسط الجملة، وكذلك "
                ATRText("עברית").backgroundColor(.systemYellow.withAlphaComponent(0.35))
                "."
            }
            .font(.systemFont(ofSize: 16))
            .lineSpacing(4)
            .paragraphSpacing(14)

            ATRParagraph {
                ATRText("Emoji ").font(.systemFont(ofSize: 15, weight: .bold)).gradient(paper)
                "families 👩‍👩‍👧‍👦 👨🏽‍💻, flags 🇨🇳 🇯🇵 🇰🇷 🇺🇳, skin tones 👋🏻👋🏼👋🏽👋🏾👋🏿, keycaps 1️⃣2️⃣3️⃣ "
                ATRText("and gradient text with 🔥 inside").gradient(ember)
                "."
            }
            .font(.systemFont(ofSize: 16))
            .lineSpacing(4)
            .paragraphSpacing(14)

            ATRParagraph {
                ATRImage(.resolved(star), size: .fixed(width: 14, height: 14)).alignment(.center)
                ATRText(" Quiz: ").font(.systemFont(ofSize: 16, weight: .bold))
                "double-tap the "
                ATRGroup {
                    ATRText("whole ").underline(ATRUnderlineStyle(pattern: .dash, thickness: 2, corners: .capsule), color: .systemPurple)
                    ATRText("phrase").underline(ATRUnderlineStyle(pattern: .dash, thickness: 2, corners: .capsule), color: .systemPurple).foregroundColor(.systemPurple)
                    ATRText(", or single-tap ")
                    ATRText("this").gradient(aurora).font(.systemFont(ofSize: 16, weight: .heavy)).onTap(value: "inner word")
                    ATRText(" inside it")
                }
                .onTap(count: 2, value: "whole phrase")
                ", or long-press the leaf "
                ATRImage(.resolved(leaf), size: .fixed(width: 16, height: 16))
                    .alignment(.center)
                    .onLongPress(value: "leaf")
                "."
            }
            .font(.systemFont(ofSize: 16))
            .lineSpacing(6)
            .paragraphSpacing(14)

            ATRParagraph {
                ATRText("H").font(mono)
                ATRText("2").font(tiny).baselineOffset(-3)
                ATRText("O + CO").font(mono)
                ATRText("2").font(tiny).baselineOffset(-3)
                ATRText(" → ").font(mono).foregroundColor(.secondaryLabel)
                ATRText("H").font(mono)
                ATRText("2").font(tiny).baselineOffset(-3)
                ATRText("CO").font(mono)
                ATRText("3").font(tiny).baselineOffset(-3)
                ATRText("     e").font(serifItalic)
                ATRText("iπ").font(tiny).baselineOffset(8)
                ATRText(" + 1 = 0").font(serif)
            }
            .alignment(.center)
            .paragraphSpacing(14)

            ATRParagraph {
                ATRText("— fin —").font(serifItalic).gradient(paper).kern(3)
            }
            .alignment(.center)
        }

        return ShowcaseSection(title: "Kitchen sink", samples: [
            ShowcaseSample(
                caption: "Nested styles, gestures, images, gradients, and many scripts in one text view",
                text: text,
                configure: { textView in
                    textView.lineHeightMode = .glyphBounds
                }
            ),
        ])
    }
}
