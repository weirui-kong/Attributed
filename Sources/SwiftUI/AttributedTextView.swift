// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import AttributedCore
import AttributedTextKit
import SwiftUI

public struct AttributedTextView: View {
    private let rendered: Attributed.RenderedAttributedText

    public init(_ content: Attributed.AttributedText) {
        rendered = content.render()
    }

    public init(rendered: Attributed.RenderedAttributedText) {
        self.rendered = rendered
    }

    public var body: some View {
        PlatformTextKitView(rendered: rendered)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if canImport(UIKit)
private struct PlatformTextKitView: UIViewRepresentable {
    let rendered: Attributed.RenderedAttributedText

    func makeUIView(context: Context) -> TextKitView {
        TextKitView()
    }

    func updateUIView(_ view: TextKitView, context: Context) {
        view.display(rendered)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: TextKitView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width > 0 else {
            return nil
        }

        uiView.display(rendered)
        return CGSize(
            width: width,
            height: uiView.heightThatFits(width: width)
        )
    }
}
#elseif canImport(AppKit)
private struct PlatformTextKitView: NSViewRepresentable {
    let rendered: Attributed.RenderedAttributedText

    func makeNSView(context: Context) -> TextKitView {
        TextKitView()
    }

    func updateNSView(_ view: TextKitView, context: Context) {
        view.display(rendered)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: TextKitView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width > 0 else {
            return nil
        }

        nsView.display(rendered)
        return CGSize(
            width: width,
            height: nsView.heightThatFits(width: width)
        )
    }
}
#endif
