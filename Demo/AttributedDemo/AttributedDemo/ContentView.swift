// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Typography") {
                    NavigationLink("Long Text") {
                        LongTextDemoView()
                    }

                    NavigationLink("Mixed Styles") {
                        MixedStylesDemoView()
                    }

                    NavigationLink("Inline Composition") {
                        InlineCompositionDemoView()
                    }

                    NavigationLink("Paragraph Layout") {
                        ParagraphDemoView()
                    }

                    NavigationLink("Text & Layout Direction") {
                        DirectionDemoView()
                    }
                }

                Section("Interaction") {
                    NavigationLink("Links") {
                        LinkDemoView()
                    }
                }

                Section("Planned") {
                    NavigationLink("Attachments") {
                        PlannedDemoView(
                            title: "Attachments",
                            message: "Synchronous image attachments will be added after the Core attachment runtime is implemented."
                        )
                    }

                    NavigationLink("Async Images") {
                        PlannedDemoView(
                            title: "Async Images",
                            message: "Async loading, placeholders, and layout updates will be tested here."
                        )
                    }
                }
            }
            .navigationTitle("Attributed Demo")
        }
    }
}
