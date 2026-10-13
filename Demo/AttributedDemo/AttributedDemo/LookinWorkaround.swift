// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import ObjectiveC
import UIKit

// LookinServer 1.2.8 hides every visible sublayer before taking a layer's solo
// screenshot, then returns early without showing them again when the layer is
// taller or wider than 20,000 points. A long text view is that tall, so after
// one Lookin capture its content, and the display view itself, stay hidden.
// This wraps the method to show again whatever it hid.
enum LookinWorkaround {
    static func install() {
        let selector = NSSelectorFromString("lks_soloScreenshotWithLowQuality:")

        guard let method = class_getInstanceMethod(CALayer.self, selector) else {
            return
        }

        typealias Original = @convention(c) (CALayer, Selector, Bool) -> UIImage?
        let original = unsafeBitCast(method_getImplementation(method), to: Original.self)
        let replacement: @convention(block) (CALayer, Bool) -> UIImage? = { layer, lowQuality in
            let visible = (layer.sublayers ?? []).filter { !$0.isHidden }
            let image = original(layer, selector, lowQuality)

            for sublayer in visible where sublayer.isHidden {
                sublayer.isHidden = false
            }

            return image
        }
        method_setImplementation(method, imp_implementationWithBlock(replacement))
    }
}
