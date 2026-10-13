// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import UIKit

// Frames per second of the main run loop, refreshed twice a second, pinned to
// the top-left corner of the window it is installed in. Touches pass through.
final class FPSMonitor: UILabel {
    private var displayLink: CADisplayLink?
    private var frames = 0
    private var windowStart: CFTimeInterval = 0
    // Sum of the refresh intervals the display link was given, so the color
    // compares against the rate the system actually runs at, which may be
    // below the screen's maximum, for example in Low Power Mode.
    private var refreshIntervals: CFTimeInterval = 0

    static func install(in window: UIWindow) {
        let monitor = FPSMonitor()
        monitor.translatesAutoresizingMaskIntoConstraints = false
        window.addSubview(monitor)
        NSLayoutConstraint.activate([
            monitor.topAnchor.constraint(equalTo: window.safeAreaLayoutGuide.topAnchor, constant: 4),
            monitor.leadingAnchor.constraint(equalTo: window.leadingAnchor, constant: 8),
        ])
        monitor.start(on: window.screen)
    }

    private override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        textColor = .white
        backgroundColor = UIColor.black.withAlphaComponent(0.65)
        layer.cornerRadius = 6
        layer.masksToBounds = true
        textAlignment = .center
        text = "-- FPS"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + 12, height: size.height + 6)
    }

    private func start(on screen: UIScreen) {
        // A weak proxy, since the display link retains its target.
        let link = CADisplayLink(target: WeakTarget(self), selector: #selector(WeakTarget.tick(_:)))
        // Variable refresh screens, such as ProMotion, run at their maximum
        // only when something asks for it, and on iPhone only with
        // CADisableMinimumFrameDurationOnPhone in Info.plist.
        let maximum = Float(screen.maximumFramesPerSecond)
        link.preferredFrameRateRange = CAFrameRateRange(minimum: maximum, maximum: maximum, preferred: maximum)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    fileprivate func tick(_ link: CADisplayLink) {
        if windowStart == 0 {
            windowStart = link.timestamp
            return
        }

        frames += 1
        refreshIntervals += link.targetTimestamp - link.timestamp
        let elapsed = link.timestamp - windowStart

        guard elapsed >= 0.5 else {
            return
        }

        let fps = Double(frames) / elapsed
        let refreshRate = Double(frames) / refreshIntervals
        textColor = Self.color(forRatio: fps / refreshRate)
        text = "\(Int(fps.rounded())) FPS"
        frames = 0
        refreshIntervals = 0
        windowStart = link.timestamp

        // Presented controllers add views to the window above this one.
        if let superview, superview.subviews.last !== self {
            superview.bringSubviewToFront(self)
        }
    }

    // Hue moves continuously from red at 40% of the refresh rate or below,
    // through yellow, to green at 95% or above.
    private static func color(forRatio ratio: Double) -> UIColor {
        let progress = min(max((ratio - 0.4) / 0.55, 0), 1)
        return UIColor(hue: progress / 3, saturation: 0.85, brightness: 0.95, alpha: 1)
    }

    deinit {
        MainActor.assumeIsolated {
            displayLink?.invalidate()
        }
    }
}

private final class WeakTarget: NSObject {
    weak var monitor: FPSMonitor?

    init(_ monitor: FPSMonitor) {
        self.monitor = monitor
    }

    @objc func tick(_ link: CADisplayLink) {
        if let monitor {
            monitor.tick(link)
        } else {
            link.invalidate()
        }
    }
}
