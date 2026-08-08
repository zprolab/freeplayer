import SwiftUI
import AppKit

/// Average color of an image (downsampled to 32x32 for speed).
private extension CGImage {
    func averageColor() -> CGColor? {
        let size = 32
        guard let ctx = CGContext(data: nil, width: size, height: size,
                                  bitsPerComponent: 8, bytesPerRow: size * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(self, in: CGRect(x: 0, y: 0, width: size, height: size))
        guard let data = ctx.data else { return nil }
        let buf = data.assumingMemoryBound(to: UInt8.self)
        var r = 0.0, g = 0.0, b = 0.0
        let count = size * size
        for i in 0..<count {
            r += Double(buf[i * 4])
            g += Double(buf[i * 4 + 1])
            b += Double(buf[i * 4 + 2])
        }
        r /= Double(count); g /= Double(count); b /= Double(count)
        return CGColor(red: r / 255, green: g / 255, blue: b / 255, alpha: 1)
    }
}

/// Manages a borderless, screen-sized window for immersive mode.
final class ImmersiveWindowController {
    static let shared = ImmersiveWindowController()
    private var window: NSWindow?

    func show(track: Track, model: AppModel) {
        guard window == nil else { return }
        guard let screen = NSScreen.main else { return }

        let host = NSHostingView(rootView: ImmersiveView(track: track).environmentObject(model))
        let win = NSWindow(contentRect: screen.frame,
                           styleMask: [.borderless],
                           backing: .buffered,
                           defer: false)
        win.isReleasedWhenClosed = false
        win.backgroundColor = .black
        win.level = .screenSaver
        win.contentView = host
        win.makeKeyAndOrderFront(nil)
        win.orderFrontRegardless()
        window = win
    }

    func hide() {
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
    }
}

/// Fullscreen dark playback overlay with karaoke lyrics.
struct ImmersiveView: View {
    @EnvironmentObject private var model: AppModel
    let track: Track

    @State private var zoom = 0
    private let zoomSteps = [-2, -1, 0, 1, 2, 3, 4]
    private var fontSize: CGFloat { 22 + CGFloat(zoom) * 4 }

    private var lyrics: [LyricLine] { LRC.parse(model.lrcContent(for: track)) }

    private var activeIndex: Int {
        var idx = -1
        for (i, line) in lyrics.enumerated() where line.time <= model.currentTime {
            idx = i
        }
        return idx
    }

    private var progress: Double {
        model.duration > 0 ? model.currentTime / model.duration : 0
    }

    var body: some View {
        ZStack {
            // Radial gradients on near-black; tint follows cover art when available
            backgroundTint.opacity(0.28)
                .ignoresSafeArea()
            RadialGradient(colors: [Theme.accent.opacity(0.16), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 500)
            RadialGradient(colors: [Theme.accent.opacity(0.10), .clear],
                           center: .bottomTrailing, startRadius: 0, endRadius: 400)
            Color.black.opacity(0.55)
        }
        .overlay {
            VStack {
                topBar
                Spacer()
                if lyrics.isEmpty {
                    noLyrics
                } else {
                    karaokeLyrics
                }
                Spacer()
                bottomControls
            }
            .padding(32)
        }
    }

    /// Dominant color of the cover art (falls back to the orange accent).
    private var backgroundTint: Color {
        guard let path = track.coverPath,
              let img = NSImage(contentsOfFile: path),
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let avg = cg.averageColor() else {
            return Theme.accent
        }
        return Color(cgColor: avg)
    }

    private var topBar: some View {
        HStack(spacing: 16) {
            CoverArtLarge(path: track.coverPath)
                .frame(width: 64, height: 64)
                .rotationEffect(.degrees(model.isPlaying ? 360 : 0))
                .animation(model.isPlaying ? .linear(duration: 20).repeatForever(autoreverses: false) : .default, value: model.isPlaying)
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                Text(track.artist)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            HStack(spacing: 10) {
                zoomButton("-", enabled: zoom > zoomSteps[0]) { zoom -= 1 }
                Text("\(Int(fontSize))px")
                    .font(Theme.mono)
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 52)
                zoomButton("+", enabled: zoom < zoomSteps.last ?? 4) { zoom += 1 }
            }
            Button {
                model.immersivePresented = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
            .help("Exit immersive mode (Esc)")
        }
    }

    private func zoomButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(enabled ? .white : .white.opacity(0.25))
                .frame(width: 28, height: 28)
                .background(.white.opacity(0.1))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var noLyrics: some View {
        VStack(spacing: 12) {
            CoverArtLarge(path: track.coverPath)
                .frame(width: 200, height: 200)
            Text(track.title)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
            Text(track.artist)
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.7))
            Text("No synced lyrics")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.top, 12)
            Text("Upload an .lrc file for this track to see time-synced lyrics here")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.3))
        }
    }

    private var karaokeLyrics: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(Array(lyrics.enumerated()), id: \.offset) { idx, line in
                        karaokeLine(line, idx: idx)
                            .id(idx)
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 40)
            }
            .onChange(of: activeIndex) { newIdx in
                guard newIdx >= 0 else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(newIdx, anchor: .center)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func karaokeLine(_ line: LyricLine, idx: Int) -> some View {
        let isActive = idx == activeIndex
        let isPast = idx < activeIndex
        let isNear = abs(idx - activeIndex) <= 2

        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(Formatting.time(line.time))
                .font(Theme.mono)
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 56, alignment: .trailing)
            Text(LRC.sanitize(line.text))
                .font(.system(size: isActive ? fontSize : max(12, fontSize - 6),
                              weight: isActive ? .semibold : .regular))
                .foregroundStyle(
                    isActive ? .white :
                    isPast ? .white.opacity(0.5) :
                    isNear ? .white.opacity(0.6) :
                    .white.opacity(0.3)
                )
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var bottomControls: some View {
        VStack(spacing: 16) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15))
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: max(geo.size.width * progress, 2))
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            model.seek(to: model.duration * value.location.x / max(geo.size.width, 1))
                        }
                )
            }
            .frame(height: 4)
            .frame(maxWidth: 900)

            HStack {
                Text(Formatting.time(model.currentTime))
                    .font(Theme.mono)
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text(Formatting.time(model.duration))
                    .font(Theme.mono)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxWidth: 900)

            HStack(spacing: 24) {
                Button { model.previous() } label: {
                    Image(systemName: "backward.fill").font(.system(size: 24)).foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                Button { model.togglePlayPause() } label: {
                    Image(systemName: model.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 46))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                Button { model.next() } label: {
                    Image(systemName: "forward.fill").font(.system(size: 24)).foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
