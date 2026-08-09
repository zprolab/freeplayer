import SwiftUI
import AppKit

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

    private var coverImage: NSImage? {
        guard let path = track.coverPath else { return nil }
        return CoverLoader.shared.image(for: path)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                immersiveBackground

                Group {
                    if lyrics.isEmpty {
                        noLyrics
                    } else {
                        karaokeLyrics
                    }
                }
                .frame(width: max(geometry.size.width - 64, 1),
                       height: max(geometry.size.height - 264, 1))
                .position(x: geometry.size.width / 2,
                          y: geometry.size.height / 2 - 20)
                .clipped()

                topBar
                    .frame(width: max(geometry.size.width - 64, 1), height: 64)
                    .position(x: geometry.size.width / 2, y: 64)

                bottomControls
                    .frame(width: max(geometry.size.width - 64, 1), height: 120, alignment: .bottom)
                    .position(x: geometry.size.width / 2,
                              y: geometry.size.height - 92)
            }
        }
    }

    @ViewBuilder
    private var immersiveBackground: some View {
        if let coverImage {
            Image(nsImage: coverImage)
                .resizable()
                .scaledToFill()
                .scaleEffect(1.12)
                .blur(radius: 72, opaque: true)
                .saturation(1.15)
                .ignoresSafeArea()
            Color.black.opacity(0.58)
                .ignoresSafeArea()
        } else {
            Color(red: 0.051, green: 0.051, blue: 0.063)
                .ignoresSafeArea()
            RadialGradient(colors: [Theme.accent.opacity(0.22), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 700)
                .ignoresSafeArea()
        }
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
            HStack(spacing: 0) {
                zoomButton("-", enabled: zoom > zoomSteps[0]) { zoom -= 1 }
                Text("\(Int(fontSize))px")
                    .font(Theme.mono)
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 52)
                zoomButton("+", enabled: zoom < zoomSteps.last ?? 4) { zoom += 1 }
            }
            .padding(.horizontal, 4)
            .frame(height: 34)
            .background(.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(.white.opacity(0.10)))
            Button {
                model.immersivePresented = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(.white.opacity(0.04)))
                    .overlay(Circle().stroke(.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .help("Exit immersive mode (Esc)")
        }
    }

    private func zoomButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(symbol)
                .font(.system(size: 14))
                .foregroundStyle(enabled ? .white : .white.opacity(0.25))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var noLyrics: some View {
        VStack(spacing: 12) {
            CoverArtLarge(path: track.coverPath)
                .frame(width: 170, height: 170)
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
        .offset(y: -40)
    }

    private var karaokeLyrics: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(Array(lyrics.enumerated()), id: \.offset) { idx, line in
                            karaokeLine(line, idx: idx)
                                .id(idx)
                        }
                    }
                    .padding(.horizontal, 80)
                    .padding(.vertical, max(geometry.size.height / 2 - fontSize, 40))
                }
                .onAppear {
                    let initialIndex = activeIndex
                    guard initialIndex >= 0 else { return }
                    DispatchQueue.main.async {
                        proxy.scrollTo(initialIndex, anchor: .center)
                    }
                }
                .onChange(of: activeIndex) { newIdx in
                    guard newIdx >= 0 else { return }
                    withAnimation(.easeInOut(duration: 0.28)) {
                        proxy.scrollTo(newIdx, anchor: .center)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        .fill(LinearGradient(colors: [Theme.accent.opacity(0.8), Theme.accent],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(geo.size.width * progress, 0))
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

            HStack {
                Text(Formatting.time(model.currentTime))
                    .font(Theme.mono)
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text(Formatting.time(model.duration))
                    .font(Theme.mono)
                    .foregroundStyle(.white.opacity(0.6))
            }
            HStack(spacing: 32) {
                Button { model.previous() } label: {
                    Image(systemName: "backward.fill").font(.system(size: 22)).foregroundStyle(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
                Button { model.togglePlayPause() } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.white)
                        .frame(width: 72, height: 72)
                        .background(Circle().fill(.white.opacity(0.1)))
                        .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                Button { model.next() } label: {
                    Image(systemName: "forward.fill").font(.system(size: 22)).foregroundStyle(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
