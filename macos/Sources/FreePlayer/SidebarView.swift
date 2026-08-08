import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @State private var playlistContext: Playlist?

    var body: some View {
        VStack(spacing: 0) {
            // Logo header (padding-top leaves room for the traffic lights)
            HStack(spacing: 10) {
                ZStack {
                    Circle().stroke(Theme.accent, lineWidth: 1.5)
                    Circle().fill(Theme.accent).frame(width: 8, height: 8)
                }
                .frame(width: 22, height: 22)
                Text("FreePlayer")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(red: 0.831, green: 0.831, blue: 0.847))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 36)
            .padding(.bottom, 16)

            // Nav
            VStack(spacing: 2) {
                navButton(.library, label: "Library", systemImage: "music.note.list", badge: model.tracks.isEmpty ? nil : "\(model.tracks.count)")
                navButton(.nowPlaying, label: "Now Playing", systemImage: "play.circle")
                navButton(.stats, label: "Statistics", systemImage: "chart.bar")
                navButton(.settings, label: "Settings", systemImage: "gearshape")
            }
            .padding(.horizontal, 8)

            // Playlists
            HStack {
                Text("Playlists")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.sidebarTextSecondary)
                    .textCase(.uppercase)
                    .tracking(0.6)
                Spacer()
                Button {
                    model.playlistSheet = PlaylistSheetState(mode: .create, playlist: nil)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.sidebarTextSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 6)

            List {
                Button {
                    model.selectPlaylist(nil)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "music.note")
                            .frame(width: 16)
                            .foregroundStyle(model.activePlaylistId == nil ? Theme.accent : Theme.sidebarTextSecondary)
                        Text("All Tracks")
                            .foregroundStyle(model.activePlaylistId == nil ? .white : Theme.sidebarTextSecondary)
                        Spacer()
                        if !model.tracks.isEmpty {
                            Text("\(model.tracks.count)")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color(red: 0.616, green: 0.616, blue: 0.639))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color(red: 0.204, green: 0.212, blue: 0.231)))
                        }
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)

                ForEach(model.playlists) { pl in
                    HStack(spacing: 10) {
                        Image(systemName: "music.note")
                            .frame(width: 16)
                            .foregroundStyle(model.activePlaylistId == pl.id ? Theme.accent : Theme.sidebarTextSecondary)
                        Text(pl.name)
                            .foregroundStyle(model.activePlaylistId == pl.id ? .white : Theme.sidebarTextSecondary)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        model.selectPlaylist(pl.id)
                    }
                    .contextMenu {
                        Button("Rename") {
                            model.playlistSheet = PlaylistSheetState(mode: .rename, playlist: pl)
                        }
                        Button("Edit Tracks") {
                            model.playlistSheet = PlaylistSheetState(mode: .edit, playlist: pl)
                        }
                        Button("Delete", role: .destructive) {
                            model.deletePlaylist(id: pl.id)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            // Footer: import
            Divider().opacity(0.5)
            Button {
                model.importSheetPresented = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.to.line")
                        .frame(width: 16)
                    Text("Import Music")
                    Spacer()
                }
            .foregroundStyle(Theme.sidebarText)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
        .background(Theme.sidebarBg)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color.black.opacity(0.15)).frame(width: 1)
        }
        // Drag & drop import overlay
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            model.handleDroppedProviders(providers)
            return true
        }
    }

    private func navButton(_ view: AppView, label: String, systemImage: String, badge: String? = nil) -> some View {
        let active = model.view == view
        return Button {
            model.view = view
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .frame(width: 18)
                    .foregroundStyle(active ? Theme.accent : Theme.sidebarTextSecondary)
                Text(label)
                    .foregroundStyle(active ? .white : Theme.sidebarTextSecondary)
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(red: 0.616, green: 0.616, blue: 0.639))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color(red: 0.204, green: 0.212, blue: 0.231)))
                }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(active ? Theme.sidebarActive : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }
}
