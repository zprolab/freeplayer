import SwiftUI
import AppKit

/// SwiftUI wrapper: live canvas + mode controls.
struct VisualizerView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if model.visualizerMode == .off {
                // Web .visualizer--off: 52px dashed strip with label + Enable.
                HStack(spacing: 10) {
                    Text("VISUALIZER OFF")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                    Button {
                        model.visualizerMode = .waveform
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                            Text("Enable")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52)
                .background(Theme.background)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [5])))
            } else {
                VisualizerCanvas(model: model)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                HStack(spacing: 4) {
                    modeButton(.waveform, icon: "waveform.path", title: "Waveform")
                    modeButton(.spectrogram, icon: "chart.bar.doc.horizontal", title: "Spectrogram")
                    modeButton(.off, icon: "xmark", title: "Turn Off")
                }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.55)))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.15), lineWidth: 1))
                .padding(8)
            }
        }
    }

    private func modeButton(_ mode: VisualizerMode, icon: String, title: String) -> some View {
        Button {
            model.visualizerMode = mode
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(model.visualizerMode == mode ? Theme.accent : .white.opacity(0.75))
                .padding(5)
                .background(model.visualizerMode == mode ? Theme.accent.opacity(0.2) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

// MARK: - NSView canvas

struct VisualizerCanvas: NSViewRepresentable {
    let model: AppModel

    func makeNSView(context: Context) -> VisualizerNSView {
        let view = VisualizerNSView()
        view.model = model
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    func updateNSView(_ nsView: VisualizerNSView, context: Context) {
        nsView.model = model
        guard let parent = nsView.superview else { return }
        // Pin edges only once — re-adding duplicates would cause Auto Layout conflicts.
        guard parent.constraints.filter({ $0.firstItem === nsView && $0.firstAttribute == .leading }).isEmpty else { return }
        NSLayoutConstraint.activate([
            nsView.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            nsView.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            nsView.topAnchor.constraint(equalTo: parent.topAnchor),
            nsView.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
        ])
    }
}

final class VisualizerNSView: NSView {
    weak var model: AppModel?

    private var timer: Timer?
    private var analyzer: AudioAnalyzer?
    private var spectrogramBuffer: [[UInt8]] = []

    // Colors
    private let waveformColor = NSColor(calibratedRed: 0.886, green: 0.263, blue: 0.161, alpha: 1)
    private let bgColor = NSColor(calibratedRed: 0.102, green: 0.102, blue: 0.118, alpha: 1)
    private let gridMinor = NSColor(calibratedRed: 0.063, green: 0.522, blue: 0.282, alpha: 0.14)
    private let gridMajor = NSColor(calibratedRed: 0.063, green: 0.522, blue: 0.282, alpha: 0.28)
    private let labelColor = NSColor(calibratedWhite: 1.0, alpha: 0.45)
    private let labelDim = NSColor(calibratedWhite: 1.0, alpha: 0.25)

    override var isFlipped: Bool { false }

    override var acceptsFirstResponder: Bool { true }

    // Force the view to fill its container — NSViews inside SwiftUI
    // NSViewRepresentable have zero intrinsic height; without this the
    // view collapses to a thin strip.
    override func layout() {
        super.layout()
        wantsLayer = true
        layer?.backgroundColor = bgColor.cgColor
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            startLoop()
        } else {
            stopLoop()
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsDisplay = true
    }

    private func startLoop() {
        guard timer == nil else { return }
        analyzer = AudioAnalyzer()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.needsDisplay = true
        }
    }

    private func stopLoop() {
        timer?.invalidate()
        timer = nil
        analyzer = nil
        spectrogramBuffer = []
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        bgColor.setFill()
        bounds.fill()

        guard let model, let analyzer, model.visualizerMode != .off else {
            drawNoSignal()
            return
        }

        let samples = model.engine.latestMonoSamples()
        analyzer.update(samples: samples)
        let freq = analyzer.getFrequencyData()
        // Playing but no audio data yet (or analyser not attached): NO SIGNAL
        // (web WaveformVisualizer draws "NO SIGNAL" instead of blank).
        let hasSignal = samples.contains { abs($0) > 0.0001 }
        if !hasSignal {
            drawNoSignal()
            return
        }
        let time = analyzer.getTimeData()

        if model.visualizerMode == .spectrogram {
            drawSpectrogram(freq, bufferLen: freq.count)
        } else {
            drawWaveformMode(freq: freq, time: time)
        }
    }

    // ── Idle ──

    private func drawNoSignal() {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: labelDim,
        ]
        let s = NSAttributedString(string: "VISUALIZER OFF", attributes: attrs)
        let size = s.size()
        s.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2 - 8))
        let enable = NSAttributedString(string: "Press V to enable", attributes: attrs)
        let eSize = enable.size()
        enable.draw(at: NSPoint(x: bounds.midX - eSize.width / 2, y: bounds.midY + 8))
    }

    // ── Waveform + spectrum mode ──

    private func drawWaveformMode(freq: [UInt8], time: [UInt8]) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let W = bounds.width
        let H = bounds.height

        let wfTop = H * 0.08
        let wfH = H * 0.47
        let divH = H * 0.02
        let spTop = wfTop + wfH + divH
        let spH = H * 0.38
        let spBaseline = spTop + spH

        drawGrid(ctx: ctx, W: W, wfTop: wfTop, wfH: wfH, spTop: spTop, spH: spH, spBaseline: spBaseline)
        drawWaveform(ctx: ctx, time: time, W: W, wfTop: wfTop, wfH: wfH)

        let maxFreq = freq.max() ?? 0
        if maxFreq > 5 {
            drawSpectrumBars(ctx: ctx, freq: freq, W: W, spTop: spTop, spH: spH)
        }
        drawLabels(ctx: ctx, W: W, H: H, wfTop: wfTop, wfH: wfH, spBaseline: spBaseline)

        // Peak indicator
        let peakW = min(CGFloat(maxFreq) / 255.0 * (W - 20), W - 20)
        ctx.setFillColor(waveformColor.withAlphaComponent(0.15 + CGFloat(maxFreq) / 255.0 * 0.4).cgColor)
        ctx.fill(CGRect(x: 10, y: H - 3, width: peakW, height: 1.5))
    }

    private func drawGrid(ctx: CGContext, W: CGFloat, wfTop: CGFloat, wfH: CGFloat, spTop: CGFloat, spH: CGFloat, spBaseline: CGFloat) {
        let wfBot = wfTop + wfH
        let spBot = spTop + spH
        let gridVCount = 16

        ctx.setStrokeColor(gridMinor.cgColor)
        ctx.setLineWidth(0.5)
        for i in 1..<gridVCount {
            let x = floor(W / CGFloat(gridVCount) * CGFloat(i)) + 0.5
            ctx.move(to: CGPoint(x: x, y: wfTop)); ctx.addLine(to: CGPoint(x: x, y: wfBot)); ctx.strokePath()
            ctx.move(to: CGPoint(x: x, y: spTop)); ctx.addLine(to: CGPoint(x: x, y: spBot)); ctx.strokePath()
        }

        let wfMid = wfTop + wfH / 2
        ctx.setStrokeColor(gridMinor.cgColor)
        for ratio in [0.25, 0.75] {
            let y = floor(wfTop + wfH * ratio) + 0.5
            ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: W, y: y)); ctx.strokePath()
        }
        ctx.setStrokeColor(gridMajor.cgColor)
        ctx.move(to: CGPoint(x: 0, y: floor(wfMid) + 0.5)); ctx.addLine(to: CGPoint(x: W, y: floor(wfMid) + 0.5)); ctx.strokePath()

        for ratio in [0.25, 0.5, 0.75] {
            let y = floor(spTop + spH * (1 - ratio)) + 0.5
            ctx.setStrokeColor(gridMinor.cgColor)
            ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: W, y: y)); ctx.strokePath()
        }
        ctx.setStrokeColor(gridMajor.cgColor)
        ctx.setLineWidth(0.6)
        ctx.move(to: CGPoint(x: 0, y: floor(spBaseline) + 0.5)); ctx.addLine(to: CGPoint(x: W, y: floor(spBaseline) + 0.5)); ctx.strokePath()
    }

    private func drawWaveform(ctx: CGContext, time: [UInt8], W: CGFloat, wfTop: CGFloat, wfH: CGFloat) {
        guard !time.isEmpty else { return }
        let midY = wfTop + wfH / 2
        let sliceW = W / CGFloat(time.count)
        let amplitude = wfH * 0.46

        func trace(_ color: NSColor, _ width: CGFloat) {
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(width)
            ctx.beginPath()
            for (i, v) in time.enumerated() {
                let y = midY + (CGFloat(v) / 128.0 - 1.0) * amplitude
                let x = CGFloat(i) * sliceW
                if i == 0 { ctx.move(to: CGPoint(x: x, y: y)) } else { ctx.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.strokePath()
        }

        trace(waveformColor.withAlphaComponent(0.22), 5)
        trace(waveformColor.withAlphaComponent(0.38), 2)
        ctx.setAlpha(0.92)
        trace(waveformColor, 1)
        ctx.setAlpha(1)
    }

    private func drawSpectrumBars(ctx: CGContext, freq: [UInt8], W: CGFloat, spTop: CGFloat, spH: CGFloat) {
        let barCount = 128
        let step = max(freq.count / barCount, 1)
        let totalW = W - 20
        let startX: CGFloat = 10
        let unit = totalW / CGFloat(barCount)
        let barW = unit * 0.68
        let gapW = unit * 0.32

        for i in 0..<barCount {
            var sum = 0
            for j in 0..<step {
                let idx = min(i * step + j, freq.count - 1)
                sum += Int(freq[idx])
            }
            let avg = CGFloat(sum) / CGFloat(step)
            let barH = avg / 255.0 * spH
            let x = startX + CGFloat(i) * (barW + gapW)
            let y = spTop + spH - barH
            let t = avg / 255.0
            let r = CGFloat(45 + t * 75) / 255.0
            let g = CGFloat(100 + t * 50) / 255.0
            let b = CGFloat(195 + t * 35) / 255.0
            ctx.setFillColor(NSColor(calibratedRed: r, green: g, blue: b, alpha: 1).cgColor)
            ctx.fill(CGRect(x: x, y: y, width: max(barW, 1.5), height: barH))
        }
    }

    private func drawLabels(ctx: CGContext, W: CGFloat, H: CGFloat, wfTop: CGFloat, wfH: CGFloat, spBaseline: CGFloat) {
        let wfMid = wfTop + wfH / 2
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: labelDim,
        ]
        draw(string: "L", at: NSPoint(x: 12, y: wfMid - 6), attrs: attrs)
        let rs = NSAttributedString(string: "R", attributes: attrs)
        draw(string: "R", at: NSPoint(x: W - 12 - rs.size().width, y: wfMid - 6), attrs: attrs)

        ctx.setStrokeColor(labelDim.cgColor)
        ctx.setLineWidth(0.5)
        let ampTop = wfTop + wfH * 0.04
        let ampBot = wfTop + wfH * 0.96
        ctx.move(to: CGPoint(x: 8, y: ampTop)); ctx.addLine(to: CGPoint(x: 16, y: ampTop)); ctx.strokePath()
        ctx.move(to: CGPoint(x: 8, y: ampBot)); ctx.addLine(to: CGPoint(x: 16, y: ampBot)); ctx.strokePath()

        let smallAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 7, weight: .regular),
            .foregroundColor: labelDim,
        ]
        draw(string: "+1", at: NSPoint(x: 18, y: ampTop - 4), attrs: smallAttrs)
        draw(string: "−1", at: NSPoint(x: 18, y: ampBot - 4), attrs: smallAttrs)

        // Divider + frequency labels
        ctx.setStrokeColor(gridMajor.cgColor)
        ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: 10, y: floor(wfTop + wfH) + 0.5))
        ctx.addLine(to: CGPoint(x: W - 10, y: floor(wfTop + wfH) + 0.5))
        ctx.strokePath()

        let freqY = spBaseline + 14
        let centerAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: labelColor,
        ]
        let labels: [(String, CGFloat)] = [("20", 0.04), ("100", 0.22), ("500", 0.40), ("2k", 0.58), ("8k", 0.76), ("20k", 0.94)]
        for (hz, frac) in labels {
            drawCentered(string: hz, x: 10 + (W - 20) * frac, y: freqY, attrs: centerAttrs)
        }
        draw(string: "Hz", at: NSPoint(x: W - 12, y: freqY), attrs: centerAttrs, alignRight: true)
    }

    // ── Spectrogram mode ──

    private func drawSpectrogram(_ freq: [UInt8], bufferLen: Int) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let W = bounds.width
        let H = bounds.height

        let marginTop: CGFloat = 18
        let marginBottom: CGFloat = 42
        let marginLeft: CGFloat = 12
        let marginRight: CGFloat = 12
        let plotW = W - marginLeft - marginRight
        let plotH = H - marginTop - marginBottom

        let numRows = max(100, min(800, Int(plotH)))
        if spectrogramBuffer.isEmpty || spectrogramBuffer[0].count != bufferLen {
            spectrogramBuffer = Array(repeating: [UInt8](repeating: 0, count: bufferLen), count: numRows)
        } else if spectrogramBuffer.count != numRows {
            resizeSpectrogram(to: numRows, bufferLen: bufferLen)
        }

        // Shift history up, append new frequency row
        spectrogramBuffer.removeFirst()
        spectrogramBuffer.append(freq)

        // Offscreen RGBA8 bitmap for the plot
        let dpr = max(window?.backingScaleFactor ?? 2, 1)
        let dw = Int((plotW * dpr).rounded())
        let dh = Int((plotH * dpr).rounded())
        guard dw > 0, dh > 0 else { return }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixels = [UInt8](repeating: 0, count: dw * dh * 4)
        let image = pixels.withUnsafeMutableBytes { (buf: UnsafeMutableRawBufferPointer) -> CGImage? in
            guard let base = buf.baseAddress,
                  let bitmapCtx = CGContext(data: base, width: dw, height: dh,
                                            bitsPerComponent: 8, bytesPerRow: dw * 4, space: colorSpace,
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

            let raw = base.assumingMemoryBound(to: UInt8.self)
            let dRowH = max(1, Int(Double(dh) / Double(numRows)))
            for row in 0..<numRows {
                let imgY = dh - 1 - Int((Double(row) / Double(numRows - 1)) * Double(dh - 1))
                let srcRow = spectrogramBuffer[row]
                let binStep = Double(bufferLen) / Double(dw)
                for px in 0..<dw {
                    let binIdx = min(Int(Double(px) * binStep), bufferLen - 1)
                    let val = Double(srcRow[binIdx]) / 255.0
                    let (r, g, b) = Theme.spectrogramColor(val)
                    for dy in 0..<dRowH where imgY + dy < dh {
                        let off = ((imgY + dy) * dw + px) * 4
                        raw[off] = UInt8(r)
                        raw[off + 1] = UInt8(g)
                        raw[off + 2] = UInt8(b)
                        raw[off + 3] = 255
                    }
                }
            }
            return bitmapCtx.makeImage()
        }

        if let image {
            ctx.interpolationQuality = .none
            ctx.draw(image, in: CGRect(x: marginLeft, y: marginTop, width: plotW, height: plotH))
        }

        // Grid overlay
        ctx.setStrokeColor(gridMinor.withAlphaComponent(0.7).cgColor)
        ctx.setLineWidth(0.5)
        for i in 1..<8 {
            let y = marginTop + (plotH / 8) * CGFloat(i)
            ctx.move(to: CGPoint(x: marginLeft, y: y))
            ctx.addLine(to: CGPoint(x: W - marginRight, y: y))
            ctx.strokePath()
        }

        // Frequency labels
        let freqY = H - 14
        let labels: [(String, CGFloat)] = [("20", 0.04), ("100", 0.22), ("500", 0.40), ("2k", 0.58), ("8k", 0.76), ("20k", 0.94)]
        for (hz, frac) in labels {
            drawCentered(string: hz, x: marginLeft + plotW * frac, y: freqY,
                         attrs: [.font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular), .foregroundColor: labelColor])
        }
        drawCentered(string: "Hz", x: W - marginRight, y: freqY,
                     attrs: [.font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular), .foregroundColor: labelDim])

        // Time labels
        draw(string: "now", at: NSPoint(x: W - marginRight + 4, y: marginTop + 8),
             attrs: [.font: NSFont.monospacedSystemFont(ofSize: 7, weight: .regular), .foregroundColor: labelDim])
        draw(string: "←", at: NSPoint(x: W - marginRight + 4, y: marginTop + plotH),
             attrs: [.font: NSFont.monospacedSystemFont(ofSize: 7, weight: .regular), .foregroundColor: labelDim])

        // Peak indicator
        let maxFreq = freq.max() ?? 0
        let peakW = min(CGFloat(maxFreq) / 255.0 * plotW, plotW)
        ctx.setFillColor(waveformColor.withAlphaComponent(0.15 + CGFloat(maxFreq) / 255.0 * 0.5).cgColor)
        ctx.fill(CGRect(x: marginLeft, y: H - 3, width: peakW, height: 1.5))
    }

    private func resizeSpectrogram(to numRows: Int, bufferLen: Int) {
        let old = spectrogramBuffer
        var newBuf: [[UInt8]] = []
        if numRows > old.count {
            let diff = numRows - old.count
            for _ in 0..<diff { newBuf.append([UInt8](repeating: 0, count: bufferLen)) }
            newBuf.append(contentsOf: old)
        } else {
            let diff = old.count - numRows
            newBuf = Array(old[diff...])
        }
        spectrogramBuffer = newBuf
    }

    // ── Text helpers ──

    private func draw(string: String, at point: NSPoint, attrs: [NSAttributedString.Key: Any], alignRight: Bool = false) {
        let s = NSAttributedString(string: string, attributes: attrs)
        var p = point
        if alignRight { p.x -= s.size().width }
        s.draw(at: p)
    }

    private func drawCentered(string: String, x: CGFloat, y: CGFloat, attrs: [NSAttributedString.Key: Any]) {
        let s = NSAttributedString(string: string, attributes: attrs)
        s.draw(at: NSPoint(x: x - s.size().width / 2, y: y))
    }
}
