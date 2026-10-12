// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import Attributed
import UIKit

final class ShowcaseViewController: UIViewController {
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let toast = ToastView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Showcase"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = .systemGroupedBackground

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        stackView.axis = .vertical
        stackView.spacing = 24
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        toast.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toast)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -96),
            stackView.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16),

            toast.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            toast.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            toast.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
        ])

        for section in ShowcaseSections.all(actions: self) {
            stackView.addArrangedSubview(makeSectionView(section))
        }
    }

    private func makeSectionView(_ section: ShowcaseSection) -> UIView {
        let header = UILabel()
        header.text = section.title.uppercased()
        header.font = .systemFont(ofSize: 13, weight: .semibold)
        header.textColor = .secondaryLabel

        let card = UIStackView()
        card.axis = .vertical
        card.spacing = 16
        card.isLayoutMarginsRelativeArrangement = true
        card.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 14

        for sample in section.samples {
            if let caption = sample.caption {
                let label = UILabel()
                label.text = caption
                label.font = .preferredFont(forTextStyle: .caption1)
                label.textColor = .tertiaryLabel
                label.numberOfLines = 0
                card.addArrangedSubview(label)
                card.setCustomSpacing(6, after: label)
            }

            let textView = ATRTextView()
            textView.delegate = self
            sample.configure(textView)
            textView.text = sample.text
            card.addArrangedSubview(textView)
        }

        let container = UIStackView(arrangedSubviews: [header, card])
        container.axis = .vertical
        container.spacing = 8
        return container
    }
}

extension ShowcaseViewController: ShowcaseActions {
    func show(_ message: String) {
        toast.show(message)
    }
}

extension ShowcaseViewController: ATRTextViewDelegate {
    func textView(_ textView: ATRTextView, didRecognize event: ATRInteractionEvent) {
        let value = event.value.map { String(describing: $0) } ?? "nil"
        toast.show("\(event.gesture) · value: \(value)\n“\(event.text)” at \(event.range.location)..<\(event.range.location + event.range.length)")
    }

    // The demo reports links instead of leaving the app.
    func textView(_ textView: ATRTextView, shouldOpen url: URL, event: ATRInteractionEvent) -> Bool {
        false
    }
}

private final class ToastView: UIVisualEffectView {
    private let label = UILabel()
    private var hideWork: DispatchWorkItem?

    init() {
        super.init(effect: UIBlurEffect(style: .systemThickMaterial))
        layer.cornerRadius = 12
        clipsToBounds = true
        alpha = 0

        label.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func show(_ message: String) {
        label.text = message
        hideWork?.cancel()
        UIView.animate(withDuration: 0.2) { self.alpha = 1 }

        let work = DispatchWorkItem { [weak self] in
            UIView.animate(withDuration: 0.3) { self?.alpha = 0 }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }
}
