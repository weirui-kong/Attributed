// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import Attributed
import AttributedUtility
import SwiftUI

@main
struct AttributedDemoApp: App {
    init() {
        ARemoteImageEnvironment.provider = ImageDownloader(
            enableDiskCache: false,
            enableMemoryCache: false
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
