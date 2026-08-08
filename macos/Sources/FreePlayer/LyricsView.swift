import SwiftUI
import AppKit

/// Time-synced LRC lyrics with auto-scroll.
struct LyricsView: View {
    let lrcContent: String?
    let currentTime: Double
    var showMetaHeader: Bool = true
    var onUpload: (() -> Void)?
    var onRemove: (() -> Void)?
    var onImmersive: (() -> Void)?
    var fontScale: CGFloat = 1.0
    var highlightCurrent: Bool = true

    private var lyrics: [LyricLine] { LRC.parse(lrcContent) }

    private var activeIndex: Int {
        var idx = -1
        for (i, line) in lyrics.enumerated() where line.time <= currentTime {
            idx = i
        }
        return idx
    }

    var body: some View {
        if lyrics.isEmpty {
            emptyState
        } else {
            VStack(spacing: 0) {
                if showMetaHeader {
                    HStack(spacing: 8) {
                        Text("LRC")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Theme.green.opacity(0.15)))
                        Text("\(lyrics.count) lines")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        if let onImmersive {
                            Button(action: onImmersive) {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .buttonStyle(.plain)
                            .help("Immersive mode")
                        }
                        if let onRemove {
                            Button(action: onRemove) {
                                Image(systemName: "trash")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .buttonStyle(.plain)
                            .help("Remove lyrics")
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(lyrics.enumerated()), id: \.offset) { idx, line in
                                lyricLine(line, idx: idx)
                                    .id(idx)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 20)
                    }
                    .onChange(of: activeIndex) { newIdx in
                        guard newIdx >= 0 else { return }
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(newIdx, anchor: .center)
                        }
                    }
                    .mask(
                        LinearGradient(gradient: Gradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.08),
                            .init(color: .black, location: 0.92),
                            .init(color: .clear, location: 1),
                        ]), startPoint: .top, endPoint: .bottom)
                    )
                }
            }
        }
    }

    private func lyricLine(_ line: LyricLine, idx: Int) -> some View {
        let isActive = idx == activeIndex
        let isPast = idx < activeIndex
        let isNear = abs(idx - activeIndex) <= 2

        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            if !isNear {
                Text(Formatting.time(line.time))
                    .font(Theme.mono)
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 40, alignment: .trailing)
                    .opacity(0)
            } else {
                Text(Formatting.time(line.time))
                    .font(Theme.mono)
                    .foregroundStyle(isActive ? Theme.accent.opacity(0.5) : Theme.textTertiary)
                    .frame(width: 40, alignment: .trailing)
            }
            Text(LRC.sanitize(line.text))
                .font(.system(size: (isActive ? 18 : 13) * fontScale, weight: isActive && highlightCurrent ? .semibold : .regular))
                .foregroundStyle(
                    isActive && highlightCurrent ? Theme.accent :
                    isPast ? Theme.textPrimary.opacity(0.5) :
                    isNear ? Theme.textSecondary.opacity(0.8) :
                    Theme.textTertiary.opacity(0.28)
                )
                .lineLimit(nil)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, isActive ? 10 : 0)
        .overlay(alignment: .leading) {
            if isActive && highlightCurrent {
                RoundedRectangle(cornerRadius: 1)
                    .fill(LinearGradient(colors: [Theme.accent.opacity(0.9), Theme.accent.opacity(0.2)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 2)
                    .frame(height: 18 * fontScale * 0.6)
                    .padding(.leading, -14)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.quote")
                .font(.system(size: 30))
                .foregroundStyle(Theme.textTertiary)
            Text("No synced lyrics")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Upload an .lrc file to see time-synced lyrics")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            if let onUpload {
                Button(action: onUpload) {
                    Label("Upload .lrc File", systemImage: "arrow.up.doc")
                }
                .buttonStyle(.bordered)
            }
            if let onImmersive {
                Button(action: onImmersive) {
                    Label("Fullscreen View", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
