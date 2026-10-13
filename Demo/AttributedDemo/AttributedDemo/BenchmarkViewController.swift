// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import Attributed
import UIKit

// Builds one large random text and shows it in a single text view, timing
// every stage: generating the random model, building the DSL value, lowering
// it, laying out the whole text, and drawing the visible part. Sync runs every
// stage on the main thread; async runs all but drawing on a background thread
// and hands the result over as prepared text.
final class BenchmarkViewController: UIViewController, UIScrollViewDelegate, ATRTextViewDelegate {
    private let sizes = [1_000, 10_000, 100_000, 1_000_000]
    private let scrollView = UIScrollView()
    private let sizeControl = UISegmentedControl(items: ["1K", "10K", "100K", "1M"])
    private let scriptControl = UISegmentedControl(items: ["English", "Mixed"])
    private let styleControl = UISegmentedControl(items: ["Plain", "Random styles", "Complex"])
    private let modeControl = UISegmentedControl(items: ["Sync", "Async"])
    private let runButton = UIButton(configuration: .filled())
    private let reportLabel = UILabel()
    private let scrollLabel = UILabel()
    private let textView = ATRTextView()
    private var textHeight: NSLayoutConstraint!
    private var assets: BenchmarkAssets?
    private var isRunning = false

    // Display link timestamps are quantized to the refresh interval, so they
    // only reveal dropped frames. The work itself is timed by run loop
    // observers: from waking up, before anything else runs, to going back
    // to sleep, after Core Animation has committed, summed per frame.
    private var displayLink: CADisplayLink?
    private var wakeObserver: CFRunLoopObserver?
    private var sleepObserver: CFRunLoopObserver?
    private var lastFrame: CFTimeInterval = 0
    private var wokeAt: CFTimeInterval = 0
    private var workThisFrame: Double = 0
    // The longest single run loop iteration since the last run finished
    // drawing, scrolling or not, such as relayouts after images load.
    private var longestStall: Double = 0
    private var lastLabelUpdate: CFTimeInterval = 0
    private var frameStats = FrameStats()
    private var lastInteraction = ""
    // Segment indexes for size, script, style, and mode, run once the page
    // appears, so a configuration can be measured from a launch argument.
    var autoRun: [Int]?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Performance"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = .systemBackground

        sizeControl.selectedSegmentIndex = 2
        scriptControl.selectedSegmentIndex = 0
        styleControl.selectedSegmentIndex = 1
        modeControl.selectedSegmentIndex = 0

        runButton.configuration?.title = "Run"
        runButton.configuration?.cornerStyle = .large
        runButton.configuration?.buttonSize = .medium
        runButton.addTarget(self, action: #selector(run), for: .primaryActionTriggered)

        reportLabel.numberOfLines = 0
        reportLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        reportLabel.text = "Pick a configuration and run."
        scrollLabel.numberOfLines = 0
        scrollLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        scrollLabel.textColor = .secondaryLabel

        // Viewport rendering keeps drawing proportional to the screen, not
        // to the text, which matters at 1M characters.
        textView.isViewportRenderingEnabled = true
        textView.delegate = self

        // Controls and results stay put; only the text scrolls.
        let panel = UIStackView(arrangedSubviews: [
            sizeControl, scriptControl, styleControl, modeControl, runButton, reportLabel, scrollLabel,
        ])
        panel.axis = .vertical
        panel.spacing = 8
        panel.setCustomSpacing(12, after: runButton)
        panel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panel)

        let separator = UIView()
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(separator)

        scrollView.delegate = self
        scrollView.alwaysBounceVertical = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        textView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(textView)
        view.addSubview(scrollView)

        textHeight = textView.heightAnchor.constraint(equalToConstant: 0)
        let content = scrollView.contentLayoutGuide
        let safeArea = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            panel.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 8),
            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            separator.topAnchor.constraint(equalTo: panel.bottomAnchor, constant: 10),
            separator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / max(1, view.traitCollection.displayScale)),
            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            textView.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24),
            textView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            textView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            textView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32),
            textHeight,
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let link = CADisplayLink(target: self, selector: #selector(frame(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link

        wakeObserver = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.afterWaiting.rawValue, true, .min) {
            [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.wokeAt = CACurrentMediaTime()
            }
        }
        sleepObserver = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, true, .max) {
            [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self, self.wokeAt > 0 else {
                    return
                }

                let work = (CACurrentMediaTime() - self.wokeAt) * 1000
                self.workThisFrame += work
                self.wokeAt = 0

                if work > self.longestStall {
                    self.longestStall = work
                    self.updateScrollLabel()
                }
            }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), wakeObserver, .commonModes)
        CFRunLoopAddObserver(CFRunLoopGetMain(), sleepObserver, .commonModes)

        if let autoRun, autoRun.count == 4 {
            self.autoRun = nil
            for (control, index) in zip([sizeControl, scriptControl, styleControl, modeControl], autoRun) {
                control.selectedSegmentIndex = index
            }
            run()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // The display link retains its target.
        displayLink?.invalidate()
        displayLink = nil

        for observer in [wakeObserver, sleepObserver].compactMap({ $0 }) {
            CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
        }

        wakeObserver = nil
        sleepObserver = nil
    }

    // MARK: - Running

    @objc private func run() {
        guard !isRunning else {
            return
        }

        isRunning = true
        runButton.isEnabled = false
        reportLabel.text = "Running…"
        view.layoutIfNeeded()

        let request = BenchmarkRequest(
            characters: sizes[sizeControl.selectedSegmentIndex],
            mixed: scriptControl.selectedSegmentIndex == 1,
            style: BenchmarkStyle(rawValue: styleControl.selectedSegmentIndex)!,
            width: textView.bounds.width,
            seed: UInt64.random(in: 1...UInt64.max),
            assets: loadAssets()
        )
        let asynchronous = modeControl.selectedSegmentIndex == 1
        // Async also draws bitmaps, and so decodes images, off the main
        // thread, which the library leaves off by default because fast
        // scrolling can then show blank tiles. Applying the layout stays
        // synchronous either way.
        textView.rendersAsynchronously = asynchronous

        // One turn of the run loop first, so "Running…" reaches the screen
        // before a synchronous run blocks the main thread.
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let start = DispatchTime.now()

                if asynchronous {
                    Task {
                        let build = await Task.detached(priority: .userInitiated) {
                            BenchmarkGenerator.build(request)
                        }.value
                        self.show(build, request: request, start: start, mainThreadStages: 0)
                    }
                } else {
                    let build = BenchmarkGenerator.build(request)
                    self.show(build, request: request, start: start, mainThreadStages: build.stageTotal)
                }
            }
        }
    }

    private func show(_ build: BenchmarkBuild, request: BenchmarkRequest, start: DispatchTime, mainThreadStages: Double) {
        let drawStart = DispatchTime.now()
        textView.setText(build.prepared)
        textHeight.constant = ceil(build.prepared.size.height)
        // Lays out the page, installs the prepared layout, and draws the
        // tiles near the visible region.
        view.layoutIfNeeded()
        let draw = milliseconds(since: drawStart)
        let total = milliseconds(since: start)

        let layout = build.prepared.layout
        let thread = mainThreadStages > 0 ? "main thread" : "background thread"
        let rows: [(String, Double)] = [
            ("Generate random text", build.generate),
            ("Build DSL value", build.buildDSL),
            ("Lower to IR", build.lower),
            ("Layout, whole text", build.layout),
            ("First draw, visible part only", draw),
        ]
        var lines = [
            "\(build.characters) chars, \(build.utf16) UTF-16, \(build.textNodes) text nodes",
            "\(build.images) images, \(build.interactions) interactions",
            "\(layout.lineCount) lines, \(Int(request.width)) x \(Int(layout.size.height.rounded(.up))) pt",
            "Built on the \(thread), seed \(String(request.seed, radix: 16))",
        ]

        if mainThreadStages == 0 {
            lines.append("Async drawing on: fast scrolling may show blank tiles")
        }
        lines += rows.map { name, value in
            "  " + name.padding(toLength: 30, withPad: " ", startingAt: 0) + formatted(value).leftPadded(to: 12)
        }
        lines += [
            "Main thread blocked: \(formatted(mainThreadStages + draw))",
            "Start to first draw: \(formatted(total))",
            "Memory footprint: \(String(format: "%.1f MB", memoryFootprint()))",
        ]
        reportLabel.text = lines.joined(separator: "\n")

        frameStats = FrameStats()
        // The iteration that just drew counts toward the report above, not
        // toward what follows.
        longestStall = 0
        wokeAt = CACurrentMediaTime()
        updateScrollLabel()
        isRunning = false
        runButton.isEnabled = true
    }

    private func loadAssets() -> BenchmarkAssets {
        if let assets {
            return assets
        }

        let loaded = BenchmarkAssets(
            icons: [
                DemoImages.symbol("star.fill", color: .systemYellow),
                DemoImages.symbol("heart.fill", color: .systemPink),
                DemoImages.symbol("cart.fill", color: .systemRed),
                DemoImages.symbol("leaf.fill", color: .systemGreen),
                DemoImages.swatch(.systemTeal),
            ],
            photo: DemoImages.landscape()
        )
        assets = loaded
        return loaded
    }

    // MARK: - Scrolling

    @objc private func frame(_ link: CADisplayLink) {
        defer {
            lastFrame = link.timestamp
            workThisFrame = 0
        }

        guard lastFrame > 0, scrollView.isDragging || scrollView.isDecelerating else {
            return
        }

        frameStats.record(
            work: workThisFrame,
            interval: (link.timestamp - lastFrame) * 1000,
            expected: (link.targetTimestamp - link.timestamp) * 1000
        )

        // Updating the label is main-thread work too; a few times a second
        // keeps it out of the numbers it reports.
        if link.timestamp - lastLabelUpdate > 0.25 {
            lastLabelUpdate = link.timestamp
            updateScrollLabel()
        }
    }

    private func updateScrollLabel() {
        let stats = frameStats
        var text = stats.frames == 0
            ? "Scroll the text to measure main-thread work per frame."
            : "Scrolling \(stats.frames) frames, main thread per frame:\n"
                + "  last \(formatted(stats.last)), avg \(formatted(stats.average)), max \(formatted(stats.max)), \(stats.dropped) dropped"

        if longestStall > 0 {
            text += "\nLongest main-thread stall since drawing: \(formatted(longestStall))"
        }

        if !lastInteraction.isEmpty {
            text += "\nLast interaction: \(lastInteraction)"
        }

        scrollLabel.text = text
    }

    // MARK: - Interactions

    func textView(_ textView: ATRTextView, didRecognize event: ATRInteractionEvent) {
        lastInteraction = "\(event.gesture) \(event.value.map { "\($0)" } ?? "action") on \"\(event.text.prefix(40))\""
        updateScrollLabel()
    }

    func textView(_ textView: ATRTextView, shouldOpen url: URL, event: ATRInteractionEvent) -> Bool {
        false
    }
}

private struct FrameStats {
    var frames = 0
    // Main-thread work, in milliseconds.
    var last: Double = 0
    var max: Double = 0
    var total: Double = 0
    // Refresh intervals that passed without a new frame.
    var dropped = 0

    var average: Double {
        frames > 0 ? total / Double(frames) : 0
    }

    mutating func record(work: Double, interval: Double, expected: Double) {
        frames += 1
        last = work
        max = Swift.max(max, work)
        total += work
        dropped += Swift.max(0, Int((interval / expected).rounded()) - 1)
    }
}

nonisolated private func milliseconds(since start: DispatchTime) -> Double {
    Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
}

private func formatted(_ milliseconds: Double) -> String {
    String(format: "%.2f ms", milliseconds)
}

private func memoryFootprint() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { raw in
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), raw, &count)
        }
    }
    return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
}

private extension String {
    func leftPadded(to length: Int) -> String {
        count >= length ? self : String(repeating: " ", count: length - count) + self
    }
}

// MARK: - Generation

nonisolated enum BenchmarkStyle: Int, Sendable {
    // One text node per paragraph with the paragraph's font.
    case plain
    // Fonts, colors, backgrounds, underlines, kerning, baseline offsets,
    // links, and paragraph alignment and spacing.
    case random
    // Everything in `random`, plus gradients in every scope, patterned and
    // gradient underlines, inline images, deferred images, and tap and long
    // press groups, some nested.
    case complex
}

nonisolated struct BenchmarkAssets: Sendable {
    let icons: [UIImage]
    let photo: UIImage
}

nonisolated struct BenchmarkRequest: Sendable {
    let characters: Int
    let mixed: Bool
    let style: BenchmarkStyle
    let width: CGFloat
    let seed: UInt64
    let assets: BenchmarkAssets
}

nonisolated struct BenchmarkBuild: Sendable {
    let prepared: ATRPreparedText
    let characters: Int
    let utf16: Int
    let textNodes: Int
    let images: Int
    let interactions: Int
    let generate: Double
    let buildDSL: Double
    let lower: Double
    let layout: Double

    var stageTotal: Double {
        generate + buildDSL + lower + layout
    }
}

// The random model is plain data, generated before any DSL value exists, so
// generating and building the DSL are timed separately.
nonisolated private struct ParagraphModel {
    var alignment = ATRTextAlignment.natural
    var lineSpacing: CGFloat = 0
    var items: [InlineModel] = []
}

nonisolated private indirect enum InlineModel {
    case text(String, SegmentStyle)
    case icon(Int, ATRAttachmentAlignment)
    case photo
    case deferredImage(Int)
    case tapGroup([InlineModel], count: Int, id: Int)
    case longPressGroup([InlineModel], id: Int)
}

nonisolated private struct SegmentStyle {
    var font: UIFont?
    var color: UIColor?
    var background: UIColor?
    var kern: CGFloat = 0
    var baselineOffset: CGFloat = 0
    var underline: ATRUnderlineStyle?
    var underlineColor: UIColor?
    var gradient: ATRTextGradient?
    var underlineGradient: ATRTextGradient?
    var link: URL?
}

nonisolated enum BenchmarkGenerator {
    static func build(_ request: BenchmarkRequest) -> BenchmarkBuild {
        var random = SplitMix64(seed: request.seed)
        var generator = ModelGenerator(request: request)

        var start = DispatchTime.now()
        let paragraphs = generator.generate(using: &random)
        let generate = milliseconds(since: start)

        start = DispatchTime.now()
        var textNodes = 0
        let text = ATRAttributedText {
            for paragraph in paragraphs {
                makeParagraph(paragraph, assets: request.assets, textNodes: &textNodes)
            }
        }
        let buildDSL = milliseconds(since: start)

        start = DispatchTime.now()
        let lowered = text.lower()
        let lower = milliseconds(since: start)

        start = DispatchTime.now()
        let layout = lowered.layout(in: ATRTextContainer(width: request.width))
        let layoutTime = milliseconds(since: start)

        return BenchmarkBuild(
            prepared: ATRPreparedText(text: text, lowered: lowered, layout: layout),
            characters: generator.characters,
            utf16: generator.utf16,
            textNodes: textNodes,
            images: generator.images,
            interactions: generator.interactions,
            generate: generate,
            buildDSL: buildDSL,
            lower: lower,
            layout: layoutTime
        )
    }

    private static func makeParagraph(_ model: ParagraphModel, assets: BenchmarkAssets, textNodes: inout Int) -> ATRParagraph {
        var nodes: [any ATRInline] = []

        for item in model.items {
            nodes.append(makeInline(item, assets: assets, textNodes: &textNodes))
        }

        return ATRParagraph {
            for node in nodes {
                node
            }
        }
        .font(benchmarkBodyFont)
        .alignment(model.alignment)
        .lineSpacing(model.lineSpacing)
        .paragraphSpacing(10)
    }

    private static func makeInline(_ model: InlineModel, assets: BenchmarkAssets, textNodes: inout Int) -> any ATRInline {
        switch model {
        case let .text(content, style):
            textNodes += 1
            return makeText(content, style: style)
        case let .icon(index, alignment):
            return ATRImage(.resolved(assets.icons[index]), size: .fixed(width: 18, height: 18)).alignment(alignment)
        case .photo:
            return ATRImage(.resolved(assets.photo), size: .fixed(width: 240, height: 120), accessibilityLabel: "Photo")
        case let .deferredImage(index):
            // Fixed, like every image here, so loading never relays out.
            let image = assets.icons[index]
            return ATRImage(.defer { image }, size: .fixed(width: 18, height: 18))
        case let .tapGroup(items, count, id):
            let children = items.map { makeInline($0, assets: assets, textNodes: &textNodes) }
            return ATRGroup<any ATRInline> {
                for child in children {
                    child
                }
            }
            .onTap(count: count, value: "tap group \(id)")
        case let .longPressGroup(items, id):
            let children = items.map { makeInline($0, assets: assets, textNodes: &textNodes) }
            return ATRGroup<any ATRInline> {
                for child in children {
                    child
                }
            }
            .onLongPress(value: "long press group \(id)")
        }
    }

    private static func makeText(_ content: String, style: SegmentStyle) -> ATRText {
        var text = ATRText(content)

        if let font = style.font {
            text = text.font(font)
        }

        if let gradient = style.gradient {
            text = text.gradient(gradient)
        } else if let color = style.color {
            text = text.foregroundColor(color)
        }

        if let background = style.background {
            text = text.backgroundColor(background)
        }

        if style.kern != 0 {
            text = text.kern(style.kern)
        }

        if style.baselineOffset != 0 {
            text = text.baselineOffset(style.baselineOffset)
        }

        if let underline = style.underline {
            if let gradient = style.underlineGradient {
                text = text.underline(underline, gradient: gradient)
            } else {
                text = text.underline(underline, color: style.underlineColor)
            }
        }

        if let link = style.link {
            text = text.link(link)
        }

        return text
    }
}

nonisolated private struct ModelGenerator {
    let request: BenchmarkRequest
    private(set) var characters = 0
    private(set) var utf16 = 0
    private(set) var images = 0
    private(set) var interactions = 0

    init(request: BenchmarkRequest) {
        self.request = request
    }

    mutating func generate(using random: inout SplitMix64) -> [ParagraphModel] {
        var paragraphs: [ParagraphModel] = []

        while characters < request.characters {
            let budget = min(request.characters - characters, Int.random(in: 80...1_200, using: &random))
            paragraphs.append(paragraph(characters: budget, using: &random))
        }

        return paragraphs
    }

    private mutating func paragraph(characters budget: Int, using random: inout SplitMix64) -> ParagraphModel {
        var model = ParagraphModel()

        if request.style != .plain {
            model.alignment = [.natural, .natural, .natural, .natural, .center, .justified, .right]
                .randomElement(using: &random)!
            model.lineSpacing = [0, 0, 2, 6].randomElement(using: &random)!
        }

        let target = characters + budget

        if request.style == .plain {
            model.items = [.text(words(until: target, using: &random), SegmentStyle())]
            return model
        }

        while characters < target {
            model.items.append(inline(until: target, depth: 0, using: &random))
        }

        return model
    }

    private mutating func inline(until target: Int, depth: Int, using random: inout SplitMix64) -> InlineModel {
        let roll = Double.random(in: 0..<1, using: &random)

        if request.style == .complex {
            switch roll {
            case ..<0.03:
                images += 1
                return .icon(
                    Int.random(in: 0..<request.assets.icons.count, using: &random),
                    [.baseline, .center, .top, .bottom].randomElement(using: &random)!
                )
            case ..<0.032:
                images += 1
                return .photo
            case ..<0.042:
                images += 1
                return .deferredImage(Int.random(in: 0..<request.assets.icons.count, using: &random))
            case ..<0.072 where depth < 2:
                interactions += 1
                let count = Double.random(in: 0..<1, using: &random) < 0.8 ? 1 : 2
                return .tapGroup(groupItems(until: target, depth: depth, using: &random), count: count, id: interactions)
            case ..<0.082 where depth < 2:
                interactions += 1
                return .longPressGroup(groupItems(until: target, depth: depth, using: &random), id: interactions)
            default:
                break
            }
        }

        let end = min(target, characters + Int.random(in: 4...60, using: &random))
        let content = words(until: end, using: &random)
        return .text(content, segmentStyle(using: &random))
    }

    private mutating func groupItems(until target: Int, depth: Int, using random: inout SplitMix64) -> [InlineModel] {
        (0..<Int.random(in: 2...4, using: &random)).map { _ in
            inline(until: max(target, characters + 1), depth: depth + 1, using: &random)
        }
    }

    // Space-separated words up to `target` characters, always at least one.
    private mutating func words(until target: Int, using random: inout SplitMix64) -> String {
        var result = ""

        repeat {
            let word = nextWord(using: &random)
            result += word.text
            result += " "
            characters += word.characters + 1
            utf16 += word.utf16 + 1
        } while characters < target

        return result
    }

    private func nextWord(using random: inout SplitMix64) -> Word {
        if request.mixed, Double.random(in: 0..<1, using: &random) < 0.45 {
            return foreignWords.randomElement(using: &random)!
        }

        let length = Int.random(in: 1...10, using: &random)
        var text = ""
        text.unicodeScalars.reserveCapacity(length)

        for _ in 0..<length {
            let upper = Double.random(in: 0..<1, using: &random) < 0.3
            let base: UInt8 = upper ? 65 : 97
            text.unicodeScalars.append(Unicode.Scalar(base + UInt8.random(in: 0..<26, using: &random)))
        }

        return Word(text: text, characters: length, utf16: length)
    }

    private func segmentStyle(using random: inout SplitMix64) -> SegmentStyle {
        var style = SegmentStyle()

        guard Double.random(in: 0..<1, using: &random) < 0.6 else {
            return style
        }

        func chance(_ probability: Double) -> Bool {
            Double.random(in: 0..<1, using: &random) < probability
        }

        if chance(0.6) {
            style.font = benchmarkFonts.randomElement(using: &random)!
        }

        if chance(0.4) {
            style.color = benchmarkColors.randomElement(using: &random)!
        }

        if chance(0.06) {
            style.background = benchmarkColors.randomElement(using: &random)!.withAlphaComponent(0.2)
        }

        if chance(0.04) {
            style.kern = [1, 2, -0.5].randomElement(using: &random)!
        }

        if chance(0.03) {
            style.baselineOffset = [-3, 3, 5].randomElement(using: &random)!
            style.font = benchmarkFonts[0]
        }

        if chance(0.08) {
            style.underline = Bool.random(using: &random) ? .single : .double
            style.underlineColor = chance(0.5) ? benchmarkColors.randomElement(using: &random)! : nil
        }

        if chance(0.05) {
            style.color = .systemBlue
            style.underline = .single
            style.link = URL(string: "https://example.com/\(Int.random(in: 0..<10_000, using: &random))")
        }

        guard request.style == .complex else {
            return style
        }

        if chance(0.12) {
            let scopeRoll = Double.random(in: 0..<1, using: &random)
            let scope: ATRGradientScope = scopeRoll < 0.7 ? .paragraph : scopeRoll < 0.97 ? .line : .document
            style.gradient = ATRTextGradient(colors: benchmarkGradients.randomElement(using: &random)!, scope: scope)
        }

        if chance(0.1) {
            let corners: ATRUnderlineStyle.Corners = [.square, .radius(1), .capsule].randomElement(using: &random)!
            style.underline = ATRUnderlineStyle(
                lines: chance(0.8) ? .single : .double,
                pattern: [.solid, .dot, .dash, .dashDot, .dashDotDot].randomElement(using: &random)!,
                thickness: [1, 2, 3, 4].randomElement(using: &random)!,
                corners: corners
            )

            if chance(0.5) {
                style.underlineGradient = ATRTextGradient(
                    colors: benchmarkGradients.randomElement(using: &random)!,
                    scope: .line
                )
            }
        }

        return style
    }
}

nonisolated private struct Word {
    let text: String
    let characters: Int
    let utf16: Int

    init(text: String, characters: Int, utf16: Int) {
        self.text = text
        self.characters = characters
        self.utf16 = utf16
    }

    init(_ text: String) {
        self.init(text: text, characters: text.count, utf16: text.utf16.count)
    }
}

// Real words, so complex scripts shape as they would in practice: Arabic and
// Hebrew are right to left, Thai, Myanmar, Tibetan, Devanagari, and
// Vietnamese stack marks above and below the line.
nonisolated private let foreignWords: [Word] = [
    "مرحبا", "العالم", "كتاب", "السلام", "عليكم", "مدينة", "جميل", "شكرا", "اللغة", "العربية",
    "שלום", "עולם", "ספר", "תודה",
    "สวัสดี", "ภาษาไทย", "ที่นี่", "น้ำ", "กรุงเทพมหานคร", "ผู้ใหญ่", "ญี่ปุ่น", "กุ้ง", "ขอบคุณ", "ฤดูร้อน",
    "မင်္ဂလာပါ", "မြန်မာ", "ကျေးဇူးတင်ပါတယ်", "စာအုပ်", "ရန်ကုန်", "နေကောင်းလား", "ဘာသာစကား", "ကြည့်", "ပြည်ထောင်စု",
    "བོད་ཡིག", "བཀྲ་ཤིས་བདེ་ལེགས",
    "नमस्ते", "हिन्दी", "भाषा", "क्षत्रिय", "धन्यवाद",
    "Tiếng", "Việt", "người", "được", "nghiêng",
    "你好", "世界", "排版", "引擎", "文字渲染", "性能测试",
    "こんにちは", "日本語", "カタカナ", "組版",
    "안녕하세요", "한국어", "글자",
    "😀", "👨‍👩‍👧‍👦", "🇨🇳", "👍🏽", "🧑🏻‍💻", "❤️",
].map(Word.init)

// A fixed set: the system caches every distinct font instance for the life
// of the process.
nonisolated private let benchmarkFonts: [UIFont] = [13, 15, 17, 20, 24].flatMap { size in
    [
        UIFont.systemFont(ofSize: size),
        UIFont.systemFont(ofSize: size, weight: .medium),
        UIFont.systemFont(ofSize: size, weight: .semibold),
        UIFont.boldSystemFont(ofSize: size),
        UIFont.italicSystemFont(ofSize: size),
    ]
}

nonisolated private let benchmarkBodyFont = UIFont.systemFont(ofSize: 17)

nonisolated private let benchmarkColors: [UIColor] = [
    .systemRed, .systemOrange, .systemGreen, .systemTeal, .systemBlue, .systemIndigo, .systemPurple, .systemPink,
    .secondaryLabel,
]

nonisolated private let benchmarkGradients: [[UIColor]] = [
    [.systemPink, .systemOrange],
    [.systemBlue, .systemPurple],
    [.systemTeal, .systemGreen, .systemYellow],
    [.systemIndigo, .systemPink, .systemOrange],
]
