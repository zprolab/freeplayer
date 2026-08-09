import SwiftUI
import AppKit

struct NowPlayingView: View {
    @EnvironmentObject private var model: AppModel
    @State private var tab: String = "overview"
    @State private var queueOpen = false
    @State private var lrcContent: String?

    var body: some View {
        Group {
            if let track = model.currentTrack {
                VStack(spacing: 0) {
                    tabBar
                    ScrollView {
                        switch tab {
                        case "lyrics":
                            LyricsView(lrcContent: lrcContent, currentTime: model.currentTime,
                                       showMetaHeader: true,
                                       emphasizeUpload: true,
                                       onUpload: { model.uploadLrc(for: track) },
                                       onFetchLyrics: { Task { await model.fetchLyrics(for: track) } },
                                       fetchingLyrics: model.lyricsFetchState == .fetching,
                                       lyricsFetchFailed: model.lyricsFetchState == .notFound,
                                       onRemove: { model.removeLrc(for: track) },
                                       onImmersive: { model.immersivePresented = true })
                                .frame(minHeight: 400)
                                .frame(maxWidth: 820)
                                .background(Theme.panel)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border.opacity(0.5)))
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 40)
                        case "scope":
                            scopeView(track: track)
                        default:
                            overview(track: track)
                        }
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "play.circle")
                        .font(.system(size: 48))
                        .foregroundStyle(Theme.textTertiary)
                    Text("Nothing playing")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Select a track from your library to start listening.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.background)
        .onAppear { lrcContent = model.lrcContent(for: model.currentTrack) }
        .onChange(of: model.currentTrack?.id) { _ in
            lrcContent = model.lrcContent(for: model.currentTrack)
        }
        .onChange(of: model.metadataRevision) { _ in
            lrcContent = model.lrcContent(for: model.currentTrack)
        }
        .onChange(of: model.immersivePresented) { presented in
            if presented, let track = model.currentTrack {
                ImmersiveWindowController.shared.show(track: track, model: model)
            } else {
                ImmersiveWindowController.shared.hide()
            }
        }
    }

    private var tabBar: some View {
        HStack {
            HStack(spacing: 4) {
                tabButton("overview", "Overview")
                tabButton("lyrics", "Lyrics")
                tabButton("scope", "Scope")
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Theme.panel)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border.opacity(0.7)))
            )
            Spacer()
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 8)
    }

    private func tabButton(_ id: String, _ label: String) -> some View {
        Button {
            tab = id
        } label: {
            Text(label)
                .font(.system(size: 12, weight: tab == id ? .semibold : .regular))
                .foregroundStyle(tab == id ? .white : Theme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(tab == id ? Theme.accent : .clear)
        }
        .buttonStyle(.plain)
    }

    // ── Overview ──

    private func overview(track: Track) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 24) {
                // Left: cover + info + spec sheet (matches web np-left column)
                VStack(alignment: .leading, spacing: 16) {
                    CoverArtLarge(path: track.coverPath,
                                  onFetchCover: { Task { await model.fetchCover(for: track) } },
                                  fetchingCover: model.coverFetchState == .fetching,
                                  coverFetchFailed: model.coverFetchState == .notFound)
                        .frame(width: 200, height: 200)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(track.artist)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                        if track.album != Track.unknownAlbum {
                            Text(track.album)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.textTertiary)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    specSheet(track)
                }
                .frame(width: 400, alignment: .leading)

                // Right: lyrics pane
                VStack(alignment: .leading, spacing: 12) {
                    LyricsView(lrcContent: lrcContent, currentTime: model.currentTime,
                               onUpload: { model.uploadLrc(for: track) },
                               onFetchLyrics: { Task { await model.fetchLyrics(for: track) } },
                               fetchingLyrics: model.lyricsFetchState == .fetching,
                               lyricsFetchFailed: model.lyricsFetchState == .notFound,
                               onRemove: { model.removeLrc(for: track) },
                               onImmersive: { model.immersivePresented = true })
                        .frame(height: 420)
                        .background(Theme.panel)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border.opacity(0.5)))
                }
            }
            .frame(maxWidth: 1000)
            .padding(.horizontal, 40)

            // Queue
            if !model.queue.isEmpty {
                queueSection
                    .frame(maxWidth: 1000)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    private func specSheet(_ track: Track) -> some View {
        // Web .np-spec: plain grid with a top border, no card chrome.
        VStack(alignment: .leading, spacing: 6) {
            if let fmt = track.fileFormat {
                specRow("Format", fmt.uppercased())
            }
            if let bitrate = track.bitrate {
                specRow("Bitrate", "\(bitrate) kbps")
            }
            if let sr = track.sampleRate {
                specRow("Sample", String(format: "%.1f kHz", sr / 1000))
            }
            if let year = track.year {
                specRow("Year", "\(year)")
            }
            if let genre = track.genre {
                specRow("Genre", genre)
            }
        }
        .padding(.top, 10)
        .overlay(alignment: .top) { Rectangle().fill(Theme.borderLight).frame(height: 1) }
    }

    private func specRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 60, alignment: .leading)
                .tracking(0.8)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var queueSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Button {
                withAnimation { queueOpen.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text("QUEUE")
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(model.queue.count)")
                        .font(Theme.mono)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Theme.panelRaised))
                    Spacer()
                    Image(systemName: queueOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)

            if queueOpen {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(model.queue.enumerated()), id: \.element.id) { idx, track in
                            Button {
                                model.play(track: track, from: model.queue)
                            } label: {
                                HStack(spacing: 10) {
                                    Group {
                                        if idx == model.queueIndex && model.isPlaying {
                                            EQIndicator().frame(width: 18)
                                        } else {
                                            Text("\(idx + 1)")
                                                .font(Theme.mono)
                                                .foregroundStyle(Theme.textTertiary)
                                        }
                                    }
                                    .frame(width: 24, alignment: .leading)
                                    Text(track.title)
                                        .lineLimit(1)
                                        .font(.system(size: 13, weight: idx == model.queueIndex ? .semibold : .regular))
                                        .foregroundStyle(idx == model.queueIndex ? Theme.accent : Theme.textPrimary)
                                    Spacer()
                                    Text(track.artist)
                                        .lineLimit(1)
                                        .foregroundStyle(Theme.textSecondary)
                                        .frame(maxWidth: 200, alignment: .trailing)
                                    Text(Formatting.time(track.duration))
                                        .font(Theme.mono)
                                        .foregroundStyle(Theme.textTertiary)
                                        .frame(width: 48, alignment: .trailing)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(idx == model.queueIndex ? Theme.accent.opacity(0.08) : .clear)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .opacity(idx < model.queueIndex ? 0.35 : 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .background(Theme.panel)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(height: min(CGFloat(model.queue.count) * 35, 300))
            }
        }
    }

    // ── Scope (visualizer) ──

    private func scopeView(track: Track) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("MONITORING")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.accent)
                Text("·")
                    .foregroundStyle(Theme.textTertiary)
                Text(track.title)
                    .foregroundStyle(Theme.textPrimary)
                Text("—")
                    .foregroundStyle(Theme.textTertiary)
                Text(track.artist)
                    .foregroundStyle(Theme.textSecondary)
                if let fmt = track.fileFormat {
                    Spacer()
                    Text(fmt.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Theme.panelRaised))
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 8)

            VisualizerView()
                .frame(maxWidth: .infinity, idealHeight: 500)
                .frame(minHeight: 280)
                .background(Theme.panel)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border.opacity(0.7)))
                .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 2)
                .padding(.horizontal, 40)
                .padding(.bottom, 16)
        }
    }
}

/// Large cover with placeholder.
struct CoverArtLarge: View {
    let path: String?
    var onFetchCover: (() -> Void)?
    var fetchingCover = false
    var coverFetchFailed = false

    var body: some View {
        if let path, let image = CoverLoader.shared.image(for: path) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border.opacity(0.6)))
                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(
                    LinearGradient(colors: [Color(red: 0.941, green: 0.941, blue: 0.953), Color(red: 0.898, green: 0.898, blue: 0.918)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "music.note")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.textTertiary)
                if let onFetchCover {
                    Button(fetchingCover ? "Fetching..." : coverFetchFailed ? "No cover found" : "Fetch Cover",
                           action: onFetchCover)
                        .buttonStyle(.plain)
                        .disabled(fetchingCover)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .offset(y: 62)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border.opacity(0.6)))
        }
    }
}

/// NSImage loader with cache (avoids re-decoding per render).
final class CoverLoader {
    static let shared = CoverLoader()
    private init() {}
    func image(for path: String) -> NSImage? {
        if let cached = CoverCache.shared.image(for: path) { return cached }
        guard let img = NSImage(contentsOfFile: path) else { return nil }
        CoverCache.shared.setImage(img, for: path)
        return img
    }
}
