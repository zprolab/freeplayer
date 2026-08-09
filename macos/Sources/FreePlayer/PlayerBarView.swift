import SwiftUI
import AppKit

struct PlayerBarView: View {
    @EnvironmentObject private var model: AppModel
    @State private var progressHover = false

    private var progress: Double {
        model.duration > 0 ? model.currentTime / model.duration : 0
    }

    var body: some View {
        VStack(spacing: 0) {
            // Thin progress line — grows to 5pt with an orange thumb on hover
            // (matches web App.css .player-progress hover behavior).
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.border.opacity(0.4))
                    Rectangle()
                        .fill(progressHover ? Theme.accentHover : Theme.accent)
                        .frame(width: max(geo.size.width * progress, 0))
                        .clipShape(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 2, bottomLeadingRadius: 2,
                                bottomTrailingRadius: progressHover ? 2 : 0,
                                topTrailingRadius: progressHover ? 2 : 0
                            )
                        )
                    if progressHover {
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 10, height: 10)
                            .offset(x: max(0, geo.size.width * progress - 5))
                    }
                }
                .contentShape(Rectangle())
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.12)) { progressHover = hovering }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            model.seek(to: model.duration * value.location.x / max(geo.size.width, 1))
                        }
                )
            }
            .frame(height: progressHover ? 5 : 1)

            HStack(spacing: 12) {
                // Track info
                HStack(spacing: 10) {
                    CoverThumb(path: model.currentTrack?.coverPath, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        if let track = model.currentTrack {
                            Text(track.title)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                            Text(track.artist)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                        } else {
                            Text("No track selected")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                            Text("Select a track from your library")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .frame(maxWidth: 200, alignment: .leading)
                }
                .frame(width: 240, alignment: .leading)

                Spacer()

                // Transport controls (web: 32x32 controls, 40px round black play)
                SystemGlassContainer(spacing: 8) {
                    HStack(spacing: 12) {
                        button(action: { model.previous() }, icon: "backward.fill", size: 16, title: "Previous")
                        Button {
                            model.togglePlayPause()
                        } label: {
                            Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 17))
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .systemGlassSurface(
                                    cornerRadius: 20,
                                    interactive: true,
                                    tint: Theme.textPrimary,
                                    fallbackFill: Theme.textPrimary
                                )
                        }
                        .buttonStyle(.plain)
                        .help(model.isPlaying ? "Pause" : "Play")
                        button(action: { model.next() }, icon: "forward.fill", size: 16, title: "Next")
                    }
                }

                Spacer()

                // Right side: play mode + time + volume
                HStack(spacing: 14) {
                    HStack(spacing: 1) {
                        playModeButton(.sequential, icon: "repeat", title: "List Loop")
                        playModeButton(.repeatOne, icon: "repeat.1", title: "Repeat One")
                        playModeButton(.shuffle, icon: "shuffle", title: "Shuffle")
                    }
                    Text("\(Formatting.time(model.currentTime)) / \(Formatting.time(model.duration))")
                        .font(Theme.mono)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(minWidth: 110)
                    Button {
                        EqualizerWindowController.shared.show(model: model)
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 13))
                            .foregroundStyle(model.equalizerEnabled ? Theme.accent : Theme.textSecondary)
                            .frame(width: 28, height: 26)
                            .systemGlassSurface(cornerRadius: 6, interactive: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Equalizer")
                    .layoutPriority(1)
                    .help("Equalizer")
                    volumeControl
                }
                .frame(width: 410, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .systemChromeBackground(fallback: Theme.playerBg)
            .overlay(alignment: .top) { Rectangle().fill(Theme.playerBorder).frame(height: 1) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .systemChromeBackground(fallback: Theme.playerBg)
    }

    private func button(action: @escaping () -> Void, icon: String, size: CGFloat, title: String) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 32, height: 32)
                .systemGlassSurface(
                    cornerRadius: 4,
                    interactive: true,
                    tint: hoveringButton == icon ? Theme.textPrimary.opacity(0.04) : nil,
                    fallbackFill: hoveringButton == icon ? Color(red: 0.910, green: 0.910, blue: 0.910) : .clear
                )
        }
        .buttonStyle(.plain)
        .onHover { hoveringButton = $0 ? icon : nil }
        .help(title)
    }

    @State private var hoveringButton: String?

    private func playModeButton(_ mode: PlayMode, icon: String, title: String) -> some View {
        Button {
            model.setPlayMode(mode)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(model.playMode == mode ? Theme.accent : Theme.textTertiary)
                .frame(width: 28, height: 26)
                .systemGlassSurface(
                    cornerRadius: 4,
                    interactive: true,
                    tint: model.playMode == mode ? Theme.accent.opacity(0.12) : nil,
                    fallbackFill: hoverMode == mode && model.playMode != mode ? Color(red: 0.910, green: 0.910, blue: 0.910) : .clear
                )
        }
        .buttonStyle(.plain)
        .onHover { hoverMode = $0 ? mode : nil }
        .help(title)
    }

    @State private var hoverMode: PlayMode?

    private var volumeControl: some View {
        HStack(spacing: 6) {
            Image(systemName: model.volume == 0 ? "speaker.slash" : (model.volume > 0.5 ? "speaker.wave.3" : "speaker.wave.1"))
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
            Slider(value: Binding(
                get: { model.volume },
                set: { model.setVolume($0) }
            ), in: 0...1)
            .controlSize(.small)
            .frame(width: 80)
        }
    }
}

/// Small cover thumbnail or a placeholder.
struct CoverThumb: View {
    let path: String?
    var size: CGFloat = 44

    var body: some View {
        if let path, let image = loadImage(path) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.panelRaised)
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(width: size, height: size)
        }
    }

    private func loadImage(_ path: String) -> NSImage? {
        if let cached = CoverCache.shared.image(for: path) { return cached }
        guard let img = NSImage(contentsOfFile: path) else { return nil }
        CoverCache.shared.setImage(img, for: path)
        return img
    }
}
