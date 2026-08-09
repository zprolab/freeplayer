import SwiftUI
import AppKit

private let eqFrequencies: [Float] = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
private let eqPresets: [(String, [Double])] = [
    ("Flat", [0,0,0,0,0,0,0,0,0,0]),
    ("Bass Boost", [6,6,5,3.5,2,0,0,0,0,0]),
    ("Vocal", [0,0,0,0,0,3,3,3,2,0]),
    ("Classical", [3,3,2,0,0,0,0,1.5,2,3]),
    ("Rock", [5,5,4,2,0,0,1,3,4.5,5]),
    ("Pop", [0.5,1,1.5,2.5,3,3,2.5,1.5,1,0.5])
]

private let eqSurface = Color.white
private let eqPanel = Color(red: 0.98, green: 0.98, blue: 0.98)
private let eqButton = Color(red: 0.96, green: 0.96, blue: 0.97)
private let eqSelected = Color(red: 0.92, green: 0.92, blue: 0.94)
private let eqBorder = Color(red: 0.86, green: 0.86, blue: 0.87)
private let eqMuted = Color(red: 0.45, green: 0.45, blue: 0.49)
private let eqAccent = Color(red: 0.90, green: 0.25, blue: 0.14)
private let eqDarkText = Color(red: 0.18, green: 0.18, blue: 0.2)

struct EqualizerView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Equalizer").font(.system(size: 25, weight: .bold)).foregroundStyle(Theme.textPrimary)
                    Text(model.equalizerEnabled ? "Active · \(model.equalizerPreset)" : "Disabled")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(model.equalizerEnabled ? eqAccent : eqMuted)
                }
                Spacer()
                Toggle("Enable", isOn: Binding(get: { model.equalizerEnabled }, set: { model.setEqualizer(enabled: $0) }))
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.textPrimary)
                    .toggleStyle(.switch).tint(eqAccent)
            }
            .padding(.horizontal, 28).padding(.vertical, 24).background(.regularMaterial)
            Divider().overlay(eqBorder)

            VStack(spacing: 20) {
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(0..<10, id: \.self) { index in
                        VStack(spacing: 7) {
                            Text(String(format: "%+.1f", model.equalizerGains[index]))
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(model.equalizerEnabled ? eqAccent : eqMuted)
                                .frame(height: 15)
                            VerticalEQSlider(value: Binding(
                                get: { model.equalizerGains[index] },
                                set: { value in
                                    var gains = model.equalizerGains
                                    gains[index] = value
                                    model.setEqualizer(preset: "Custom", gains: gains)
                                }
                            ), enabled: model.equalizerEnabled)
                            .frame(height: 108)
                            Text(label(for: eqFrequencies[index]))
                                .font(.system(size: 13, design: .monospaced)).foregroundStyle(eqMuted)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                Divider().overlay(eqBorder)
                SystemGlassContainer(spacing: 8, alwaysOn: true) {
                    HStack(spacing: 10) {
                        Text("Presets").font(.system(size: 15, weight: .semibold)).foregroundStyle(eqMuted)
                        ForEach(eqPresets, id: \.0) { preset in
                            Button { model.setEqualizer(enabled: true, preset: preset.0, gains: preset.1) } label: {
                                Text(preset.0).font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(model.equalizerPreset == preset.0 ? eqDarkText : eqMuted)
                                    .padding(.horizontal, 15).padding(.vertical, 8)
                                    .systemGlassSurface(
                                        cornerRadius: 18,
                                        interactive: true,
                                        tint: model.equalizerPreset == preset.0 ? eqSelected.opacity(0.75) : nil,
                                        alwaysOn: true
                                    )
                            }.buttonStyle(.plain)
                        }
                        Spacer()
                        Button { model.setEqualizer(enabled: false, preset: "Flat", gains: eqPresets[0].1) } label: {
                            Text("Reset").font(.system(size: 14, weight: .medium)).foregroundStyle(eqMuted)
                                .padding(.horizontal, 17).padding(.vertical, 8)
                                .systemGlassSurface(cornerRadius: 18, interactive: true, alwaysOn: true)
                        }.buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 28).padding(.vertical, 22).background(.ultraThinMaterial)
        }
        .frame(width: 760, height: 390)
        .background(.regularMaterial)
    }

    private func label(for frequency: Float) -> String {
        frequency >= 1000 ? "\(Int(frequency / 1000))K" : "\(Int(frequency))"
    }
}

private struct VerticalEQSlider: View {
    @Binding var value: Double
    let enabled: Bool
    private let range = -12.0...12.0
    @State private var isDragging = false
    @State private var isSettling = false
    @State private var inertiaOffset: CGFloat = 0
    @State private var interactionGeneration = 0

    var body: some View {
        GeometryReader { geometry in
            let height = max(geometry.size.height, 1)
            let normalized = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let inset: CGFloat = 14
            let usableHeight = max(height - inset * 2, 1)
            let thumbY = inset + usableHeight * (1 - normalized)
            let zeroY = inset + usableHeight * 0.5
            ZStack {
                Capsule().fill(eqBorder.opacity(0.95)).frame(width: 6, height: usableHeight)
                Capsule().fill(enabled ? Color.accentColor.opacity(0.48) : eqMuted.opacity(0.35))
                    .frame(width: 6, height: max(abs(zeroY - thumbY), 2))
                    .offset(y: (zeroY + thumbY) / 2 - height / 2)
                RoundedRectangle(cornerRadius: 6)
                    .fill(.clear)
                    .frame(width: 22, height: 28)
                    .modifier(EQGlassModifier(enabled: enabled, isInteracting: isDragging || isSettling))
                    .scaleEffect(x: isDragging ? 1.16 : 1.0, y: isDragging ? 0.84 : 1.0)
                    .position(x: geometry.size.width / 2, y: thumbY + inertiaOffset)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { gesture in
                    if !isDragging {
                        interactionGeneration += 1
                        isSettling = false
                        inertiaOffset = 0
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                            isDragging = true
                        }
                    }
                    let clamped = min(max(gesture.location.y, inset), height - inset)
                    let next = range.lowerBound + (1 - (clamped - inset) / usableHeight) * (range.upperBound - range.lowerBound)
                    value = (next * 2).rounded() / 2
                }
                .onEnded { gesture in
                    let projectedDelta = gesture.predictedEndLocation.y - gesture.location.y
                    let projectedOffset = min(max(projectedDelta * 0.06, -10), 10)
                    interactionGeneration += 1
                    let releaseGeneration = interactionGeneration
                    isDragging = false
                    isSettling = true
                    withAnimation(.easeOut(duration: 0.08)) {
                        inertiaOffset = projectedOffset
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                            inertiaOffset = 0
                        }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                        guard interactionGeneration == releaseGeneration else { return }
                        isSettling = false
                    }
                })
        }
        .frame(width: 32)
    }
}

private struct EQGlassModifier: ViewModifier {
    let enabled: Bool
    let isInteracting: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(
                    .regular
                        .tint(enabled && !isInteracting ? eqAccent.opacity(0.55) : nil)
                        .interactive(),
                    in: .rect(cornerRadius: 6)
                )
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(enabled && !isInteracting ? eqAccent.opacity(0.82) : .white.opacity(0.92))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(
                                    LinearGradient(
                                        colors: [.white.opacity(0.34), .clear],
                                        startPoint: .top,
                                        endPoint: .center
                                    )
                                )
                        )
                )
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(eqBorder.opacity(0.9), lineWidth: 0.8))
                .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
        }
    }
}

final class EqualizerWindowController {
    static let shared = EqualizerWindowController()
    private var window: NSWindow?

    func show(model: AppModel) {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let host = NSHostingController(rootView: EqualizerView().environmentObject(model))
        let window = NSWindow(contentViewController: host)
        window.title = "Equalizer"
        window.styleMask = [.titled, .closable]
        window.backgroundColor = NSColor(calibratedWhite: 0.075, alpha: 1)
        window.minSize = NSSize(width: 760, height: 390)
        window.isReleasedWhenClosed = false
        window.center(); window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }
}
