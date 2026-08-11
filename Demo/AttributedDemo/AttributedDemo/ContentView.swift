// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationView {
            List {
                Section("Showcase") {
                    NavigationLink("All Features") {
                        FeatureShowcaseDemoView()
                    }
                }

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

                Section("Attachments") {
                    NavigationLink("Image Overview") {
                        ImageDemoView()
                    }

                    NavigationLink("Sizing") {
                        ImageSizingDemoView()
                    }

                    NavigationLink("Inline Alignment") {
                        ImageAlignmentDemoView()
                    }

                    NavigationLink("Wrapping & Long Text") {
                        ImageWrappingDemoView()
                    }

                    NavigationLink("Image Direction") {
                        ImageDirectionDemoView()
                    }

                    NavigationLink("Async States") {
                        AsyncImageStatesDemoView()
                    }

                    NavigationLink("Remote Images") {
                        RemoteImageDemoView()
                    }

                    NavigationLink("Remote Gallery") {
                        RemoteImageGalleryDemoView()
                    }
                }
            }
            .navigationTitle("Attributed Demo")
        }
        #if os(iOS)
        .navigationViewStyle(.stack)
        #endif
    }
}
