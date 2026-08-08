import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var model: AppModel

    private struct SortCol: Identifiable {
        var id: String { key }
        let key: String
        let label: String
        let width: CGFloat?
    }

    private let sortCols: [SortCol] = [
        .init(key: "title", label: "Title", width: nil),
        .init(key: "artist", label: "Artist", width: 180),
        .init(key: "album", label: "Album", width: 200),
        .init(key: "duration", label: "Duration", width: 90),
        .init(key: "imported_at", label: "Added", width: 130),
    ]

    var body: some View {
        Group {
            if model.displayedTracks.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    header
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(model.displayedTracks.enumerated()), id: \.element.id) { index, track in
                                TrackRow(track: track, index: index)
                                if track.id != model.displayedTracks.last?.id {
                                    Divider().opacity(0.3).padding(.leading, 54)
                                }
                            }
                        }
                        .padding(.bottom, 8)
                    }
                }
            }
        }
        .background(Theme.background)
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text("#")
                .frame(width: 44, alignment: .leading)
                .padding(.leading, 10)
            ForEach(sortCols) { col in
                sortHeaderButton(col)
            }
            Spacer(minLength: 8)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Theme.textSecondary)
        .padding(.vertical, 8)
        .background(Theme.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    private func sortHeaderButton(_ col: SortCol) -> some View {
        Button {
            if model.sortBy == col.key {
                model.sortDir = model.sortDir == "ASC" ? "DESC" : "ASC"
            } else {
                model.sortBy = col.key
                model.sortDir = (col.key == "title" || col.key == "artist") ? "ASC" : "DESC"
            }
            model.loadTracks()
        } label: {
            HStack(spacing: 4) {
                Text(col.label)
                if model.sortBy == col.key {
                    Image(systemName: model.sortDir == "ASC" ? "arrow.up" : "arrow.down")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.accent)
                } else {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.textTertiary.opacity(0.5))
                }
            }
            .frame(width: col.width, alignment: .leading)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note")
                .font(.system(size: 48))
                .foregroundStyle(Theme.textTertiary)
            Text("No tracks yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Import your music to start building your library.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TrackRow: View {
    @EnvironmentObject private var model: AppModel
    let track: Track
    let index: Int
    @State private var hovering = false

    private var isActive: Bool { model.currentTrack?.id == track.id }

    var body: some View {
        HStack(spacing: 0) {
            // Index / EQ
            Group {
                if isActive && model.isPlaying {
                    EQIndicator()
                        .frame(width: 24)
                } else if isActive {
                    Text("▶")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 24)
                } else {
                    Text("\(index + 1)")
                        .font(Theme.mono)
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 24)
                }
            }
            .frame(width: 44, alignment: .leading)
            .padding(.leading, 10)

            // Title + format badge
            HStack(spacing: 6) {
                Text(track.title)
                    .lineLimit(1)
                    .foregroundStyle(isActive ? Theme.blue : Theme.textPrimary)
                if let fmt = track.fileFormat {
                    Text(fmt.uppercased())
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Color(red: 0.941, green: 0.941, blue: 0.953)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(track.artist)
                .lineLimit(1)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 180, alignment: .leading)

            Text(track.album)
                .lineLimit(1)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 200, alignment: .leading)

            Text(Formatting.tableDuration(track.duration))
                .font(Theme.mono)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 90, alignment: .leading)

            Text(Formatting.compactDate(track.importedAt))
                .font(Theme.mono)
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 130, alignment: .leading)

            Button {
                model.play(track: track, from: model.displayedTracks)
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 26, height: 22)
                    .background(Circle().fill(Theme.accent))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 12)
        }
        .font(.system(size: 13))
        .padding(.vertical, 6)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            model.play(track: track, from: model.displayedTracks)
        }
        .contextMenu {
            trackMenu
        }
    }

    private var rowBackground: Color {
        if isActive {
            return hovering ? Theme.blue.opacity(0.12) : Theme.blue.opacity(0.08)
        }
        return hovering ? Color(red: 0.961, green: 0.961, blue: 0.973) : .clear
    }

    @ViewBuilder private var trackMenu: some View {
        Button {
            model.editTrack = track
        } label: {
            Label("Edit Metadata", systemImage: "pencil")
        }

        Menu {
            if model.playlists.isEmpty {
                Text("No playlists yet")
            } else {
                ForEach(model.playlists) { pl in
                    Button(pl.name) {
                        model.addToPlaylist(playlistId: pl.id, trackId: track.id)
                    }
                }
            }
            Divider()
            Button("New Playlist...") {
                model.pendingAddTrack = track
                model.playlistSheet = PlaylistSheetState(mode: .create, playlist: nil)
            }
        } label: {
            Label("Add to Playlist", systemImage: "plus.circle")
        }

        Button {
            model.uploadLrc(for: track)
        } label: {
            Label("Upload Lyrics...", systemImage: "text.quote")
        }
        .disabled(track.lrcPath != nil)

        if track.lrcPath != nil {
            Button {
                model.removeLrc(for: track)
            } label: {
                Label("Remove Lyrics", systemImage: "trash")
            }
        }

        if model.activePlaylistId != nil {
            Button(role: .destructive) {
                model.removeFromPlaylist(trackId: track.id)
            } label: {
                Label("Remove from Playlist", systemImage: "xmark")
            }
        }

        Button(role: .destructive) {
            model.deleteTrack(track)
        } label: {
            Label("Delete Track", systemImage: "trash")
        }
    }
}

/// Three animated EQ bars, shown on the playing row (matches web: 2px wide,
/// 8/14/10px tall, 0.8s cycle with staggered delay).
struct EQIndicator: View {
    @State private var animating = false

    private let heights: [CGFloat] = [8, 14, 10]
    private let delays: [Double] = [0, 0.15, 0.3]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: 2)
                    .frame(height: animating ? heights[i] : heights[i] * 0.5)
                    .animation(.easeInOut(duration: 0.4).delay(delays[i]).repeatForever(autoreverses: true), value: animating)
            }
        }
        .frame(height: 18)
        .onAppear { animating = true }
    }
}
