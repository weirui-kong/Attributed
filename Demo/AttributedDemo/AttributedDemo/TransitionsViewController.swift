// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import Attributed
import Combine
import SwiftUI
import UIKit

// Each sample shows the numeric text transition in an Attributed text view
// above SwiftUI's own `.contentTransition(.numericText())` with the same
// font and text, so the two can be compared frame by frame.
final class TransitionsViewController: UIViewController {
    private struct Sample {
        let title: String
        let font: UIFont
        let format: (Int) -> String
    }

    private let samples = [
        Sample(title: "Counter", font: .systemFont(ofSize: 44, weight: .semibold)) { "\($0)" },
        Sample(title: "Price", font: .systemFont(ofSize: 32, weight: .bold)) { value in
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.locale = Locale(identifier: "en_US")
            return formatter.string(from: NSNumber(value: Double(value) / 100)) ?? ""
        },
        Sample(title: "In a sentence", font: .systemFont(ofSize: 20)) { "You have \($0) unread messages" },
    ]

    private let model = TransitionModel()
    private var textViews: [ATRTextView] = []
    private let stackView = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Transitions"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = .systemGroupedBackground

        // Builds the Metal pipeline before the first tap.
        DispatchQueue.global(qos: .userInitiated).async {
            _ = ATRTextTransition.prewarmNumericText()
        }

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        stackView.axis = .vertical
        stackView.spacing = 24
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        let controls = makeControls()
        controls.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controls)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: controls.topAnchor, constant: -8),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16),
            stackView.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16),

            controls.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            controls.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            controls.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
        ])

        for (index, sample) in samples.enumerated() {
            stackView.addArrangedSubview(makeCard(for: sample, index: index))
        }
    }

    private func makeCard(for sample: Sample, index: Int) -> UIView {
        let card = UIStackView()
        card.axis = .vertical
        card.spacing = 8
        card.isLayoutMarginsRelativeArrangement = true
        card.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 14

        card.addArrangedSubview(caption(sample.title.uppercased(), weight: .semibold))
        card.addArrangedSubview(caption("Attributed", weight: .regular))

        let textView = ATRTextView()
        textView.text = text(sample.format(model.value), font: sample.font)
        textViews.append(textView)
        card.addArrangedSubview(textView)

        card.addArrangedSubview(caption("SwiftUI", weight: .regular))

        if #available(iOS 17.0, *) {
            let host = UIHostingController(rootView: SwiftUINumericText(model: model, font: sample.font, format: sample.format))
            host.sizingOptions = .intrinsicContentSize
            host.view.backgroundColor = .clear
            addChild(host)
            card.addArrangedSubview(host.view)
            host.didMove(toParent: self)
        } else {
            card.addArrangedSubview(caption("Needs iOS 17", weight: .regular))
        }

        return card
    }

    private func makeControls() -> UIView {
        let controls = UIStackView()
        controls.axis = .horizontal
        controls.distribution = .fillEqually
        controls.spacing = 8

        for (title, change) in [("−1", -1), ("+1", 1), ("+99", 99), ("Random", 0)] {
            var configuration = UIButton.Configuration.filled()
            configuration.title = title
            let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
                self?.apply(change)
            })
            controls.addArrangedSubview(button)
        }

        return controls
    }

    // A decreasing value rolls downward, like SwiftUI's numericText(value:).
    private func apply(_ change: Int) {
        let next = change == 0 ? Int.random(in: 0...200_000) : max(0, model.value + change)
        let direction: ATRNumericTextDirection = next < model.value ? .downward : .upward

        withAnimation {
            model.countsDown = direction == .upward
            model.value = next
        }

        for (sample, textView) in zip(samples, textViews) {
            textView.setText(text(sample.format(next), font: sample.font), transition: .numericText(direction))
        }
    }

    private func text(_ string: String, font: UIFont) -> ATRAttributedText {
        ATRAttributedText {
            ATRParagraph {
                ATRText(string).font(font).foregroundColor(.label)
            }
        }
    }

    private func caption(_ string: String, weight: UIFont.Weight) -> UILabel {
        let label = UILabel()
        label.text = string
        label.font = .systemFont(ofSize: 13, weight: weight)
        label.textColor = .secondaryLabel
        return label
    }
}

final class TransitionModel: ObservableObject {
    @Published var value = 1_299
    // SwiftUI's `countsDown: true` rolls upward, matching `.upward`.
    @Published var countsDown = false
}

@available(iOS 17.0, *)
private struct SwiftUINumericText: View {
    @ObservedObject var model: TransitionModel
    let font: UIFont
    let format: (Int) -> String

    var body: some View {
        Text(format(model.value))
            .font(Font(font))
            .foregroundStyle(Color(uiColor: .label))
            .contentTransition(.numericText(countsDown: model.countsDown))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
