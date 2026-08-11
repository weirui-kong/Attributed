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
        ATextView(rendered: rendered)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PlannedDemoView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "hammer")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            SwiftUI.Text(title)
                .font(.headline)

            SwiftUI.Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .navigationTitle(title)
    }
}
