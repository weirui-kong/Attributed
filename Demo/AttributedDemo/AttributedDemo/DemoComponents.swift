// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import Attributed
import SwiftUI

struct DemoSection: View {
    let title: String
    let rendered: ARenderedAttributedText
    let details: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                RenderedSample(rendered: rendered)

                Divider()

                SwiftUI.Text(details)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle(title)
    }
}

struct RenderedSample: View {
    let rendered: ARenderedAttributedText

    var body: some View {
        SwiftUI.Text(AttributedString(rendered.attributedString))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PlannedDemoView: View {
    let title: String
    let message: String

    var body: some View {
        ContentUnavailableView(
            title,
            systemImage: "hammer",
            description: SwiftUI.Text(message)
        )
        .navigationTitle(title)
    }
}
