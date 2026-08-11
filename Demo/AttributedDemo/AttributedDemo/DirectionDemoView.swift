// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import Attributed
import SwiftUI

struct DirectionDemoView: View {
    private let leftToRight = AAttributedText {
        AParagraph {
            "English text flows from left to right, followed by العربية and עברית inline."
        }
        .font(.systemFont(ofSize: 18))
        .baseWritingDirection(.leftToRight)
        .alignment(.left)
    }.render()

    private let rightToLeft = AAttributedText {
        AParagraph {
            "هذا نص عربي من اليمين إلى اليسار، ويتضمن English و־עברית ضمن السطر نفسه."
        }
        .font(.systemFont(ofSize: 18))
        .baseWritingDirection(.rightToLeft)
        .alignment(.right)
    }.render()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                sample("LTR paragraph", rendered: leftToRight)
                sample("RTL paragraph", rendered: rightToLeft)
                layoutDirectionSample
            }
            .padding()
        }
        .navigationTitle("Text & Layout Direction")
    }

    private func sample(
        _ title: String,
        rendered: ARenderedAttributedText
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SwiftUI.Text(title).font(.headline)
            RenderedSample(rendered: rendered)
                .padding()
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var layoutDirectionSample: some View {
        VStack(alignment: .leading, spacing: 10) {
            SwiftUI.Text("SwiftUI layout direction").font(.headline)

            directionRow("Left to right", icon: "arrow.right")
                .environment(\.layoutDirection, .leftToRight)

            directionRow("Right to left", icon: "arrow.left")
                .environment(\.layoutDirection, .rightToLeft)
        }
    }

    private func directionRow(_ title: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
            SwiftUI.Text(title)
            Spacer()
            Image(systemName: "chevron.forward")
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}
