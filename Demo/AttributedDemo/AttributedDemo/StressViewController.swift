// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import Attributed
import os
import UIKit

// Hammers text view lifecycles to shake out crashes, leaks of state, and
// hangs:
// - Every frame runs random chains of operations, mostly on one focused
//   view, mixing hierarchy moves, option toggles, text replacement, forced
//   layout, measurement, deferred continuations, and nested chains.
// - Background workers lower random documents and lay out a shared pool of
//   documents at random widths, concurrently with each other and with the
//   views' asynchronous rendering.
// - A watchdog measures main-thread stalls and counts hangs.
// Main-thread chains are reproducible from the seed; background timing is not.
final class StressViewController: UIViewController {
    fileprivate enum Step: String, CaseIterable {
        case create, release, park, unpark, moveView, moveWrapper, detachScrollView
        case toggleViewport, toggleAsync, tileHeight, lineHeightMode, maxLines, emojiGradient
        case replaceText, clearText, resize, scroll, appearance
        case forceLayout, measure, readLayout, deferRest, nestedChain
    }

    private let firstScrollView = UIScrollView()
    private let secondScrollView = UIScrollView()
    // Fixed hosts own the layout constraints, so a scroll view can leave the
    // window and come back without losing its frame.
    private let firstHost = UIView()
    private let secondHost = UIView()
    private let statsLabel = UILabel()
    private var wrappers: [UIView] = []
    private var liveViews: [ATRTextView] = []
    // Views removed from the hierarchy but kept alive, to be re-added later.
    private var parked: [ATRTextView] = []
    // The view a chain mostly works on, so steps compound on one object.
    private var focus: ATRTextView?
    private var counts: [Step: Int] = [:]
    private var chains = 0
    private var lastChain: [Step] = []
    private var random = SplitMix64(seed: 1)
    private var seed: UInt64 = 1
    private var displayLink: CADisplayLink?
    private var ticks = 0
    private let background = BackgroundStress()
    private let maxLiveViews = 60
    // Set before the page appears to run for a fixed time and then go back.
    var autoRunSeconds: TimeInterval?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Stress"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(title: "Start", style: .plain, target: self, action: #selector(toggleRunning)),
            UIBarButtonItem(title: "Reset", style: .plain, target: self, action: #selector(reset)),
        ]

        for (host, scrollView) in [(firstHost, firstScrollView), (secondHost, secondScrollView)] {
            host.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(host)
            scrollView.backgroundColor = .secondarySystemBackground
            scrollView.contentSize = CGSize(width: 0, height: 2400)
            scrollView.layer.cornerRadius = 10
            scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            host.addSubview(scrollView)
        }

        statsLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        statsLabel.numberOfLines = 0
        statsLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statsLabel)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            firstHost.topAnchor.constraint(equalTo: guide.topAnchor, constant: 8),
            firstHost.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 8),
            firstHost.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -8),
            firstHost.heightAnchor.constraint(equalTo: secondHost.heightAnchor),

            secondHost.topAnchor.constraint(equalTo: firstHost.bottomAnchor, constant: 8),
            secondHost.leadingAnchor.constraint(equalTo: firstHost.leadingAnchor),
            secondHost.trailingAnchor.constraint(equalTo: firstHost.trailingAnchor),

            statsLabel.topAnchor.constraint(equalTo: secondHost.bottomAnchor, constant: 8),
            statsLabel.leadingAnchor.constraint(equalTo: firstHost.leadingAnchor),
            statsLabel.trailingAnchor.constraint(equalTo: firstHost.trailingAnchor),
            statsLabel.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -8),
            statsLabel.heightAnchor.constraint(equalToConstant: 120),
        ])

        reset()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        guard let seconds = autoRunSeconds else { return }

        autoRunSeconds = nil
        start()
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            self?.stop()
            self?.navigationController?.popViewController(animated: false)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stop()
    }

    // MARK: - Control

    @objc private func toggleRunning() {
        displayLink == nil ? start() : stop()
    }

    private func start() {
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
        background.start()
        navigationItem.rightBarButtonItems?.first?.title = "Pause"
    }

    private func stop() {
        displayLink?.invalidate()
        displayLink = nil
        background.stop()
        navigationItem.rightBarButtonItems?.first?.title = "Start"
    }

    @objc private func reset() {
        stop()
        liveViews.forEach { $0.removeFromSuperview() }
        wrappers.forEach { $0.removeFromSuperview() }
        liveViews = []
        parked = []
        focus = nil
        counts = [:]
        chains = 0
        lastChain = []
        ticks = 0
        seed = UInt64.random(in: 1...UInt64.max)
        random = SplitMix64(seed: seed)
        background.reset()
        overrideUserInterfaceStyle = .unspecified

        // Wrappers sit between the scroll views and the text views, so moving
        // one moves an ancestor of its text views between scroll views.
        wrappers = (0..<4).map { index in
            let wrapper = UIView(frame: CGRect(x: 0, y: CGFloat(index) * 600, width: 360, height: 600))
            wrapper.layer.borderColor = UIColor.separator.cgColor
            wrapper.layer.borderWidth = 0.5
            (index.isMultiple(of: 2) ? firstScrollView : secondScrollView).addSubview(wrapper)
            return wrapper
        }

        updateStats()
    }

    @objc private func tick() {
        ticks += 1

        for _ in 0..<Int.random(in: 1...4, using: &random) {
            runChain(randomChain(), depth: 0)
        }

        updateStats()
    }

    // MARK: - Chains

    private func randomChain() -> [Step] {
        (0..<Int.random(in: 2...10, using: &random)).map { _ in Step.allCases.randomElement(using: &random)! }
    }

    private func runChain(_ chain: [Step], depth: Int) {
        chains += 1
        lastChain = chain
        focus = liveViews.randomElement(using: &random)

        for (index, step) in chain.enumerated() {
            if step == .deferRest {
                // Finish the chain on a later main-queue turn, after layout,
                // asynchronous drawing, and deferred image loads interleave.
                counts[step, default: 0] += 1
                let rest = Array(chain[(index + 1)...])
                DispatchQueue.main.async { [weak self] in
                    self?.runChain(rest, depth: depth)
                }
                return
            }

            perform(step, depth: depth)
        }
    }

    // MARK: - Steps

    private func perform(_ step: Step, depth: Int) {
        counts[step, default: 0] += 1

        switch step {
        case .create:
            guard liveViews.count < maxLiveViews else { return perform(.release, depth: depth) }
            let textView = ATRTextView()
            configureRandomly(textView)
            textView.text = StressDocuments.random(using: &random)
            textView.frame = randomFrame()
            randomWrapper().addSubview(textView)
            liveViews.append(textView)
            focus = textView
        case .release:
            guard let textView = target() else { return }
            textView.removeFromSuperview()
            liveViews.removeAll { $0 === textView }
            parked.removeAll { $0 === textView }
            if focus === textView { focus = nil }
        case .park:
            guard let textView = target(), textView.superview != nil else { return }
            textView.removeFromSuperview()
            parked.append(textView)
        case .unpark:
            guard !parked.isEmpty else { return }
            let textView = parked.remove(at: Int.random(in: 0..<parked.count, using: &random))
            randomWrapper().addSubview(textView)
            focus = textView
        case .moveView:
            guard let textView = target() else { return }
            randomWrapper().addSubview(textView)
            parked.removeAll { $0 === textView }
        case .moveWrapper:
            randomScrollView().addSubview(randomWrapper())
        case .detachScrollView:
            // Takes a whole scroll view out of the window and puts it back,
            // so every text view inside leaves and re-enters the window.
            let first = Bool.random(using: &random)
            let scrollView = first ? firstScrollView : secondScrollView
            let host = first ? firstHost : secondHost
            scrollView.removeFromSuperview()
            scrollView.frame = host.bounds
            host.addSubview(scrollView)
        case .toggleViewport:
            target()?.isViewportRenderingEnabled.toggle()
        case .toggleAsync:
            target()?.rendersAsynchronously.toggle()
        case .tileHeight:
            target()?.tileHeight = [16, 32, 64, 128, 256].randomElement(using: &random)!
        case .lineHeightMode:
            target()?.lineHeightMode = Bool.random(using: &random) ? .glyphBounds : .typographic
        case .maxLines:
            target()?.maximumNumberOfLines = Int.random(in: 0...4, using: &random)
        case .emojiGradient:
            target()?.appliesGradientToEmoji.toggle()
        case .replaceText:
            target()?.text = StressDocuments.random(using: &random)
        case .clearText:
            target()?.text = nil
        case .resize:
            target()?.frame = randomFrame()
        case .scroll:
            let scrollView = randomScrollView()
            let maxOffset = max(1, scrollView.contentSize.height - scrollView.bounds.height)
            scrollView.setContentOffset(
                CGPoint(x: 0, y: CGFloat.random(in: 0...maxOffset, using: &random)),
                animated: Bool.random(using: &random)
            )
        case .appearance:
            overrideUserInterfaceStyle = [.light, .dark, .unspecified].randomElement(using: &random)!
        case .forceLayout:
            // Lay out synchronously in the middle of the chain instead of
            // waiting for the next pass.
            (Bool.random(using: &random) ? view : target())?.layoutIfNeeded()
        case .measure:
            _ = target()?.measuredSize(forWidth: CGFloat.random(in: -20...500, using: &random))
        case .readLayout:
            _ = target()?.textLayout?.size
        case .deferRest:
            break
        case .nestedChain:
            guard depth < 3 else { return }
            let saved = focus
            runChain(randomChain(), depth: depth + 1)
            focus = saved
        }
    }

    // The focused view most of the time, sometimes any live view.
    private func target() -> ATRTextView? {
        if let focus, liveViews.contains(where: { $0 === focus }), Int.random(in: 0..<10, using: &random) < 7 {
            return focus
        }

        let view = liveViews.randomElement(using: &random)
        focus = view ?? focus
        return view
    }

    private func randomWrapper() -> UIView {
        wrappers.randomElement(using: &random)!
    }

    private func randomScrollView() -> UIScrollView {
        Bool.random(using: &random) ? firstScrollView : secondScrollView
    }

    private func randomFrame() -> CGRect {
        CGRect(
            x: CGFloat.random(in: 0...40, using: &random),
            y: CGFloat.random(in: 0...560, using: &random),
            width: CGFloat.random(in: 0...320, using: &random),
            height: CGFloat.random(in: 0...700, using: &random)
        )
    }

    private func configureRandomly(_ textView: ATRTextView) {
        textView.isViewportRenderingEnabled = Bool.random(using: &random)
        textView.rendersAsynchronously = Bool.random(using: &random)
        textView.tileHeight = [16, 32, 64, 128, 256].randomElement(using: &random)!
        textView.maximumNumberOfLines = Int.random(in: 0...3, using: &random)
        textView.lineHeightMode = Bool.random(using: &random) ? .glyphBounds : .typographic
    }

    private func updateStats() {
        let stats = background.snapshot()
        let operations = counts.values.reduce(0, +)
        let hang = stats.hangs > 0 ? "  ⚠️ HANGS \(stats.hangs)" : ""
        statsLabel.textColor = stats.hangs > 0 ? .systemRed : .label
        statsLabel.text = """
        seed \(seed)   ticks \(ticks)   chains \(chains)   steps \(operations)
        live \(liveViews.count)   attached \(liveViews.filter { $0.superview != nil }.count)   parked \(parked.count)
        bg lowered \(stats.lowered)   bg layouts \(stats.layouts)   pool \(stats.poolSize)
        main stall max \(Int(stats.maxStall * 1000)) ms\(hang)
        last chain: \(lastChain.map(\.rawValue).joined(separator: " → "))
        """
    }
}

// Background pressure: workers lower random documents and lay out a shared
// pool of documents at random widths, all at once; a watchdog measures how
// long the main thread takes to answer.
nonisolated final class BackgroundStress: @unchecked Sendable {
    struct Stats {
        var lowered = 0
        var layouts = 0
        var poolSize = 0
        var hangs = 0
        var maxStall: TimeInterval = 0
    }

    private struct State {
        var running = false
        var generation = 0
        var stats = Stats()
        var pool: [ATRIR.Document] = []
        var lastMainBeat = Date()
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let workerCount = 4
    private let hangThreshold: TimeInterval = 1

    func start() {
        let generation = state.withLock { state -> Int? in
            guard !state.running else { return nil }
            state.running = true
            state.generation += 1
            state.lastMainBeat = Date()
            return state.generation
        }

        guard let generation else { return }

        for worker in 0..<workerCount {
            Thread.detachNewThread { [self] in
                runWorker(seed: UInt64(worker + 1) &* 0x9E37_79B9, generation: generation)
            }
        }

        Thread.detachNewThread { [self] in
            runWatchdog(generation: generation)
        }
    }

    func stop() {
        state.withLock { $0.running = false }
    }

    func reset() {
        state.withLock { state in
            state.running = false
            state.stats = Stats()
            state.pool = []
        }
    }

    func snapshot() -> Stats {
        state.withLock { $0.stats }
    }

    private func isCurrent(_ generation: Int) -> Bool {
        state.withLock { $0.running && $0.generation == generation }
    }

    private func runWorker(seed: UInt64, generation: Int) {
        var random = SplitMix64(seed: seed ^ UInt64(Date().timeIntervalSince1970 * 1000))

        while isCurrent(generation) {
            // A detached thread's own pool only drains when the thread exits.
            autoreleasepool {
                runWorkerIteration(using: &random)
            }
        }
    }

    private func runWorkerIteration(using random: inout SplitMix64) {
        if Int.random(in: 0..<3, using: &random) == 0 {
            // Lower off the main thread and publish into the shared pool,
            // replacing a document other workers may be laying out.
            let document = BackgroundDocuments.random(using: &random).lower().document
            let slot = Int.random(in: 0..<1024, using: &random)
            state.withLock { state in
                state.stats.lowered += 1

                if state.pool.count < 12 {
                    state.pool.append(document)
                } else {
                    state.pool[slot % state.pool.count] = document
                }

                state.stats.poolSize = state.pool.count
            }
        }

        let pick = Int.random(in: 0..<1024, using: &random)
        let document = state.withLock { state in
            state.pool.isEmpty ? nil : state.pool[pick % state.pool.count]
        }

        guard let document else { return }

        let container = ATRTextContainer(
            width: CGFloat.random(in: 1...600, using: &random),
            maxHeight: Bool.random(using: &random) ? .infinity : CGFloat.random(in: 0...400, using: &random),
            maximumNumberOfLines: Int.random(in: 0...5, using: &random),
            truncationToken: ["…", "...", " more", ""].randomElement(using: &random)!,
            lineHeightMode: Bool.random(using: &random) ? .glyphBounds : .typographic
        )
        let layout = document.layout(in: container)
        _ = (layout.size, layout.lineCount, layout.isTruncated)
        state.withLock { $0.stats.layouts += 1 }
    }

    private func runWatchdog(generation: Int) {
        while isCurrent(generation) {
            DispatchQueue.main.async { [self] in
                state.withLock { $0.lastMainBeat = Date() }
            }

            Thread.sleep(forTimeInterval: 0.25)

            state.withLock { state in
                let stall = Date().timeIntervalSince(state.lastMainBeat)
                state.stats.maxStall = max(state.stats.maxStall, stall)

                if stall > hangThreshold {
                    state.stats.hangs += 1
                }
            }
        }
    }
}

// Deterministic, so a failing run can be replayed from its seed.
nonisolated struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

nonisolated private let stressSnippets = [
    "The quick brown fox jumps over the lazy dog.",
    "中文排版讲究标点挤压与避头尾。",
    "日本語の文章、カタカナ、ひらがな。",
    "한국어 문장입니다.",
    "مرحبا بالعالم",
    "שלום עולם",
    "ภาษาไทยไม่มีการเว้นวรรค",
    "ကျွန်ုပ်တို့၏ မြန်မာစာ",
    "Ελληνικά γράμματα",
    "हिन्दी देवनागरी",
    "Emoji 🎉👩‍👩‍👧‍👦🇨🇳1️⃣",
    "a\u{0301}\u{0301}\u{0301} zalgo",
    "\u{200F}\u{202E}bidi override\u{202C}",
    "",
]

// A fixed set of sizes: the system caches every distinct font instance
// forever, so continuous random sizes would grow memory without bound.
nonisolated private let stressFontSizes: [CGFloat] = [1, 9, 11, 13, 15, 17, 20, 24, 30, 40]

nonisolated private let stressColors: [UIColor] = [
    .systemRed, .systemOrange, .systemGreen, .systemBlue, .systemPurple, .label,
]

// Documents built off the main thread: every text feature except images,
// whose platform objects are made on the main thread in StressDocuments.
nonisolated enum BackgroundDocuments {
    static func random(using random: inout SplitMix64) -> ATRAttributedText {
        let paragraphs = (0..<Int.random(in: 0...6, using: &random)).map { _ in paragraph(using: &random) }
        return ATRAttributedText {
            for paragraph in paragraphs {
                paragraph
            }
        }
    }

    static func paragraph(using random: inout SplitMix64) -> ATRParagraph {
        let pieces = (0..<Int.random(in: 0...6, using: &random)).map { _ in text(using: &random) }
        let alignments: [ATRTextAlignment] = [.natural, .left, .center, .right, .justified]
        let directions: [ATRWritingDirection] = [.natural, .leftToRight, .rightToLeft]
        return ATRParagraph {
            for piece in pieces {
                piece
            }
        }
        .font(.systemFont(ofSize: stressFontSizes.randomElement(using: &random)!))
        .alignment(alignments.randomElement(using: &random)!)
        .baseWritingDirection(directions.randomElement(using: &random)!)
        .lineSpacing(CGFloat.random(in: 0...12, using: &random))
        .paragraphSpacing(CGFloat.random(in: 0...16, using: &random))
    }

    static func text(using random: inout SplitMix64) -> any ATRInline {
        let snippet = stressSnippets.randomElement(using: &random)!

        switch Int.random(in: 0..<8, using: &random) {
        case 0:
            return ATRText(snippet).foregroundColor(stressColors.randomElement(using: &random)!)
        case 1:
            return ATRText(snippet).gradient(gradient(using: &random))
        case 2:
            return ATRText(snippet).underline(underline(using: &random), color: stressColors.randomElement(using: &random)!)
        case 3:
            return ATRText(snippet).gradient(gradient(using: &random)).underline(underline(using: &random), gradient: gradient(using: &random))
        case 4:
            return ATRText(snippet).kern(CGFloat.random(in: -2...6, using: &random)).baselineOffset(CGFloat.random(in: -8...8, using: &random))
        case 5:
            return ATRText(snippet).backgroundColor(.systemYellow.withAlphaComponent(0.3)).onTap(count: Int.random(in: 1...3, using: &random), value: snippet)
        case 6:
            let first = stressSnippets.randomElement(using: &random)!
            let second = stressSnippets.randomElement(using: &random)!
            return ATRGroup {
                ATRText(first).font(.boldSystemFont(ofSize: stressFontSizes.randomElement(using: &random)!))
                ATRGroup {
                    ATRText(second).link(URL(string: "https://example.com")!)
                }
                .onLongPress(minimumDuration: 0.2, value: second)
            }
            .onTap(value: first)
        default:
            return ATRText(snippet)
        }
    }

    static func gradient(using random: inout SplitMix64) -> ATRTextGradient {
        let scopes: [ATRGradientScope] = [.line, .paragraph, .document]
        let count = Int.random(in: 2...4, using: &random)
        return ATRTextGradient(
            colors: (0..<count).map { _ in stressColors.randomElement(using: &random)! },
            locations: Bool.random(using: &random) ? (0..<count).map { CGFloat($0) / CGFloat(count - 1) } : nil,
            startPoint: [.left, .top, .topLeft, .center].randomElement(using: &random)!,
            endPoint: [.right, .bottom, .bottomRight, .center].randomElement(using: &random)!,
            scope: scopes.randomElement(using: &random)!
        )
    }

    static func underline(using random: inout SplitMix64) -> ATRUnderlineStyle {
        let patterns: [ATRUnderlineStyle.Pattern] = [.solid, .dot, .dash, .dashDot, .dashDotDot]
        let corners: [ATRUnderlineStyle.Corners] = [.square, .capsule, .radius(CGFloat.random(in: 0...4, using: &random))]
        return ATRUnderlineStyle(
            lines: Bool.random(using: &random) ? .single : .double,
            pattern: patterns.randomElement(using: &random)!,
            thickness: Bool.random(using: &random) ? nil : CGFloat.random(in: 0.1...8, using: &random),
            corners: corners.randomElement(using: &random)!
        )
    }
}

// Main-thread documents: the background mix plus images through both
// pipelines.
enum StressDocuments {
    static func random(using random: inout SplitMix64) -> ATRAttributedText {
        let paragraphs = (0..<Int.random(in: 0...6, using: &random)).map { _ in paragraph(using: &random) }
        return ATRAttributedText {
            for paragraph in paragraphs {
                paragraph
            }
        }
    }

    private static func paragraph(using random: inout SplitMix64) -> ATRParagraph {
        let pieces = (0..<Int.random(in: 0...6, using: &random)).map { _ in inline(using: &random) }
        return ATRParagraph {
            for piece in pieces {
                piece
            }
        }
        .font(.systemFont(ofSize: stressFontSizes.randomElement(using: &random)!))
        .lineSpacing(CGFloat.random(in: 0...12, using: &random))
    }

    private static func inline(using random: inout SplitMix64) -> any ATRInline {
        switch Int.random(in: 0..<4, using: &random) {
        case 0:
            return ATRImage(
                .resolved(DemoImages.swatch(stressColors.randomElement(using: &random)!)),
                size: .fixed(width: CGFloat.random(in: 1...40, using: &random), height: CGFloat.random(in: 1...40, using: &random))
            )
            .alignment([.baseline, .center, .top, .bottom, .offset(-4)].randomElement(using: &random)!)
        case 1:
            let width = CGFloat.random(in: 1...300, using: &random)
            return ATRImage(
                .defer { DemoImages.landscape(size: CGSize(width: 120, height: 60)) },
                size: Bool.random(using: &random) ? .adaptive(maxWidth: width) : .fixed(width: width, height: width / 2)
            )
            .onTap(value: "image")
        default:
            return BackgroundDocuments.text(using: &random)
        }
    }
}
