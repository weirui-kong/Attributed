// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import Attributed
import UIKit

// Renders the README examples, each in its own text view, to PNG files in
// light and dark appearance under Documents/readme, for the screenshots in
// the README. Opened with the `-readmeShots` launch argument. The texts
// mirror the README's code blocks; keep them in sync.
final class ReadmeShotsViewController: UIViewController {
    private struct Shot {
        let name: String
        let text: ATRAttributedText
        var configure: (ATRTextView) -> Void = { _ in }
    }

    private let width: CGFloat = 390
    private let padding: CGFloat = 20
    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "README shots"
        view.backgroundColor = .systemBackground
        statusLabel.numberOfLines = 0
        statusLabel.frame = view.bounds.insetBy(dx: 20, dy: 120)
        statusLabel.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(statusLabel)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("readme")
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        render(shots(), index: 0, into: directory)
    }

    private func render(_ shots: [Shot], index: Int, into directory: URL) {
        guard index < shots.count * 2 else {
            statusLabel.text = "Wrote \(shots.count * 2) images to\n\(directory.path)"
            NSLog("README_SHOTS_DONE %@", directory.path)
            return
        }

        let shot = shots[index / 2]
        let style: UIUserInterfaceStyle = index % 2 == 0 ? .light : .dark
        let card = UIView(frame: CGRect(x: 0, y: 0, width: width, height: 10))
        card.overrideUserInterfaceStyle = style
        card.backgroundColor = .systemBackground
        let textView = ATRTextView()
        shot.configure(textView)
        textView.text = shot.text
        card.addSubview(textView)

        let textWidth = width - padding * 2
        let height = ceil(textView.measuredSize(forWidth: textWidth).height)
        textView.frame = CGRect(x: padding, y: padding, width: textWidth, height: height)
        card.frame.size.height = height + padding * 2
        // Off screen but in the window, so trait changes and drawing happen.
        card.frame.origin = CGPoint(x: -width * 2, y: 0)
        view.addSubview(card)
        card.layoutIfNeeded()

        // Deferred images load on the next main-queue turn; give them time.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            MainActor.assumeIsolated {
                card.layoutIfNeeded()
                let format = UIGraphicsImageRendererFormat()
                format.scale = 2
                let image = UIGraphicsImageRenderer(bounds: card.bounds, format: format).image { _ in
                    card.drawHierarchy(in: card.bounds, afterScreenUpdates: true)
                }
                let suffix = style == .light ? "light" : "dark"
                let url = directory.appendingPathComponent("\(shot.name)-\(suffix).png")
                try? image.pngData()?.write(to: url)
                card.removeFromSuperview()
                self.statusLabel.text = "Rendered \(shot.name)-\(suffix)"
                self.render(shots, index: index + 1, into: directory)
            }
        }
    }

    private func shots() -> [Shot] {
        let sunset = ATRTextGradient(colors: [.systemPink, .systemOrange])
        let star = DemoImages.symbol("star.fill", color: .systemYellow)
        let cover = DemoImages.landscape(size: CGSize(width: 360, height: 240))
        let docsURL = URL(string: "https://example.com/docs")!

        return [
            Shot(name: "text", text: ATRAttributedText {
                ATRParagraph {
                    "Hello, "
                    ATRText("Attributed")
                        .font(.boldSystemFont(ofSize: 17))
                        .foregroundColor(.systemPink)
                    "!"
                }
                .font(.systemFont(ofSize: 17))
                .lineSpacing(4)
            }),
            Shot(name: "gradients", text: ATRAttributedText {
                ATRParagraph {
                    ATRText("Warm")
                        .gradient(sunset)
                    " plain "
                    ATRText("glow")
                        .gradient(sunset)
                }
                .font(.systemFont(ofSize: 28, weight: .heavy))

                ATRParagraph {
                    ATRText("Dashed")
                        .underline(ATRUnderlineStyle(pattern: .dash, thickness: 2), color: .systemBlue)
                    "  "
                    ATRText("Capsule")
                        .underline(ATRUnderlineStyle(thickness: 4, corners: .capsule), gradient: sunset)
                    "  E = mc"
                    ATRText("2")
                        .font(.systemFont(ofSize: 11))
                        .baselineOffset(7)
                }
            }),
            Shot(name: "images", text: ATRAttributedText {
                ATRParagraph {
                    "Rated "
                    ATRImage(.resolved(star), size: .fixed(width: 16, height: 16))
                        .alignment(.center)
                    " 4.9, cover: "
                    ATRImage(.defer { cover }, size: .fixed(width: 120, height: 80))
                }
            }),
            Shot(name: "interactions", text: ATRAttributedText {
                ATRParagraph {
                    "Read the "
                    ATRText("docs")
                        .foregroundColor(.systemBlue)
                        .link(docsURL)
                    ", double-tap "
                    ATRText("this")
                        .onTap(count: 2, value: 42)
                    ", or hold "
                    ATRGroup<any ATRInline> {
                        ATRText("several ")
                            .font(.boldSystemFont(ofSize: 17))
                        ATRText("nodes")
                    }
                    .onLongPress(minimumDuration: 0.5) {}
                }
            }),
            Shot(name: "options", text: ATRAttributedText {
                ATRParagraph {
                    "Thai ภาษาไทย ญี่ปุ่น ผู้ใหญ่ and Myanmar မြန်မာ ကျေးဇူးတင်ပါတယ် get lines tall enough for their stacked marks, "
                    "and text that runs past three lines ends with a custom token instead of being cut off mid-word "
                    "somewhere you cannot see it."
                }
                .font(.systemFont(ofSize: 17))
            }, configure: { textView in
                textView.maximumNumberOfLines = 3
                textView.truncationToken = "… more"
                textView.lineHeightMode = .glyphBounds
            }),
        ]
    }
}
