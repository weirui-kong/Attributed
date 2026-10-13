// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import UIKit

final class HomeViewController: UITableViewController {
    private struct Demo {
        let title: String
        let subtitle: String
        let symbol: String
        let makeViewController: () -> UIViewController
    }

    private let demos: [Demo] = [
        Demo(
            title: "Showcase",
            subtitle: "Every feature, mixed styles, and mixed content",
            symbol: "sparkles.rectangle.stack",
            makeViewController: { ShowcaseViewController() }
        ),
        Demo(
            title: "Performance",
            subtitle: "Up to 1M characters in one text view, timed stage by stage",
            symbol: "speedometer",
            makeViewController: { BenchmarkViewController() }
        ),
        Demo(
            title: "Stress",
            subtitle: "Random lifecycle operations every frame",
            symbol: "bolt.horizontal.circle",
            makeViewController: { StressViewController() }
        ),
    ]

    init() {
        super.init(style: .insetGrouped)
        title = "Attributed"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Demo")
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        demos.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let demo = demos[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "Demo", for: indexPath)
        var content = UIListContentConfiguration.subtitleCell()
        content.text = demo.title
        content.secondaryText = demo.subtitle
        content.secondaryTextProperties.color = .secondaryLabel
        content.image = UIImage(systemName: demo.symbol)
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        navigationController?.pushViewController(demos[indexPath.row].makeViewController(), animated: true)
    }
}
