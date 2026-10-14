// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import Attributed
import UIKit

// Loops the numeric text transition through a fixed cycle of values on a
// plain card, for the README's animated image. Opened with the
// `-readmeTransition` launch argument, optionally followed by `dark`. The
// card's frame in points is logged as README_TRANSITION_CARD so a screen
// recording can be cropped to it.
final class ReadmeTransitionViewController: UIViewController {
    // Prices in cents with unread counts; the cycle returns to its start, so
    // a recording of one cycle loops seamlessly.
    private let steps = [(1_299, 3), (1_349, 4), (12_800, 12), (999, 9)]
    private let width: CGFloat = 390
    private let padding: CGFloat = 24
    private let price = ATRTextView()
    private let message = ATRTextView()
    private var index = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let card = UIView()
        card.backgroundColor = .systemBackground
        view.addSubview(card)
        card.addSubview(price)
        card.addSubview(message)

        let textWidth = width - padding * 2
        price.text = priceText(steps[0].0)
        message.text = messageText(steps[0].1)
        let priceHeight = ceil(price.measuredSize(forWidth: textWidth).height)
        let messageHeight = ceil(message.measuredSize(forWidth: textWidth).height)
        price.frame = CGRect(x: padding, y: padding, width: textWidth, height: priceHeight)
        message.frame = CGRect(x: padding, y: padding + priceHeight + 8, width: textWidth, height: messageHeight)
        let height = padding * 2 + priceHeight + 8 + messageHeight
        card.frame = CGRect(x: ((view.bounds.width - width) / 2).rounded(), y: 300, width: width, height: height)
        NSLog("README_TRANSITION_CARD %@", NSCoder.string(for: card.frame))
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        DispatchQueue.global(qos: .userInitiated).async {
            _ = ATRTextTransition.prewarmNumericText()
        }
        Timer.scheduledTimer(withTimeInterval: 1.6, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.advance()
            }
        }
    }

    private func advance() {
        let previous = steps[index]
        index = (index + 1) % steps.count
        let next = steps[index]
        let direction: ATRNumericTextDirection = next.0 < previous.0 ? .downward : .upward
        price.setText(priceText(next.0), transition: .numericText(direction))
        message.setText(messageText(next.1), transition: .numericText(direction))
    }

    private func priceText(_ cents: Int) -> ATRAttributedText {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_US")
        let string = formatter.string(from: NSNumber(value: Double(cents) / 100)) ?? ""
        let rounded = UIFont.systemFont(ofSize: 48, weight: .bold).fontDescriptor
            .withDesign(.rounded)
            .map { UIFont(descriptor: $0, size: 48) } ?? .systemFont(ofSize: 48, weight: .bold)

        return ATRAttributedText {
            ATRParagraph {
                ATRText(string)
                    .font(rounded)
                    .gradient(ATRTextGradient(colors: [.systemPink, .systemOrange]))
            }
        }
    }

    private func messageText(_ count: Int) -> ATRAttributedText {
        ATRAttributedText {
            ATRParagraph {
                "You have "
                ATRText("\(count)")
                    .font(.systemFont(ofSize: 20, weight: .semibold))
                " unread messages"
            }
            .font(.systemFont(ofSize: 20))
            .foregroundColor(.label)
        }
    }
}
