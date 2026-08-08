import SwiftUI

/// Create / rename / edit playlist sheet (with a searchable track picker).
struct PlaylistSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let sheet: PlaylistSheetState

    @State private var name = ""
    @State private var description = ""
    @State private var selectedIds = Set<Int64>()
    @State private var pickerQuery = ""
    @State private var loaded = false

    private var isRename: Bool { sheet.mode == .rename }
    private var showPicker: Bool { sheet.mode != .rename }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                if sheet.mode == .edit, let name = sheet.playlist?.name {
                    Text("— \(name)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(14)

            Divider()

            VStack(spacing: 14) {
                if !isRename {
                    field("Name") {
                        TextField("My Playlist", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }
                    field("Description") {
                        TextField("A few words about this playlist...", text: $description)
                            .textFieldStyle(.roundedBorder)
                    }
                } else {
                    field("Name") {
                        TextField("Playlist name", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                if showPicker {
                    trackPicker
                }
            }
            .padding(14)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Button(action: submit) {
                    Text(submitLabel)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(isRename ? name.trimmingCharacters(in: .whitespaces).isEmpty : name.trimmingCharacters(in: .whitespaces).isEmpty && sheet.mode == .create)
            }
            .padding(14)
        }
        .frame(width: showPicker ? 680 : 420, height: showPicker ? 560 : 200)
        .background(Theme.background)
        .onAppear(perform: setup)
    }

    private var title: String {
        switch sheet.mode {
        case .create: return "New Playlist"
        case .rename: return "Rename Playlist"
        case .edit: return "Edit Playlist Tracks"
        }
    }

    private var submitLabel: String {
        switch sheet.mode {
        case .create: return "Create"
        case .rename: return "Rename"
        case .edit: return "Save"
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)
            content()
        }
    }

    private var filteredTracks: [Track] {
        let q = pickerQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return model.tracks }
        return model.tracks.filter {
            $0.title.lowercased().contains(q) ||
            $0.artist.lowercased().contains(q) ||
            $0.album.lowercased().contains(q)
        }
    }

    private var trackPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select Tracks")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                    TextField("Filter tracks...", text: $pickerQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Theme.panelRaised)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border))

                let allFilteredSelected = !filteredTracks.isEmpty && filteredTracks.allSatisfy { selectedIds.contains($0.id) }
                Button(allFilteredSelected ? "Clear" : "Select All") {
                    if allFilteredSelected {
                        filteredTracks.forEach { selectedIds.remove($0.id) }
                    } else {
                        filteredTracks.forEach { selectedIds.insert($0.id) }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Text("\(selectedIds.count) selected")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }

            ScrollView {
                VStack(spacing: 0) {
                    if filteredTracks.isEmpty {
                        Text(model.tracks.isEmpty ? "No tracks in library" : "No tracks match your search")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.vertical, 30)
                    } else {
                        ForEach(filteredTracks) { track in
                            HStack(spacing: 10) {
                                Toggle("", isOn: Binding(
                                    get: { selectedIds.contains(track.id) },
                                    set: { on in
                                        if on { selectedIds.insert(track.id) } else { selectedIds.remove(track.id) }
                                    }
                                ))
                                .toggleStyle(.checkbox)
                                .labelsHidden()
                                Text(track.title)
                                    .lineLimit(1)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Text(track.artist)
                                    .lineLimit(1)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.textSecondary)
                                    .frame(maxWidth: 140, alignment: .trailing)
                                Text(track.album)
                                    .lineLimit(1)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.textTertiary)
                                    .frame(maxWidth: 120, alignment: .trailing)
                                Text(Formatting.time(track.duration))
                                    .font(Theme.mono)
                                    .foregroundStyle(Theme.textTertiary)
                                    .frame(width: 44, alignment: .trailing)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(selectedIds.contains(track.id) ? Theme.accent.opacity(0.08) : .clear)
                        }
                    }
                }
                .padding(4)
            }
            .frame(maxHeight: 320)
            .background(Theme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func setup() {
        guard !loaded else { return }
        loaded = true
        switch sheet.mode {
        case .create:
            if let pending = model.pendingAddTrack {
                selectedIds = [pending.id]
            }
        case .rename:
            name = sheet.playlist?.name ?? ""
        case .edit:
            if let id = sheet.playlist?.id {
                selectedIds = Set(Database.shared.playlistTracks(playlistId: id).map(\.id))
            }
        }
    }

    private func submit() {
        switch sheet.mode {
        case .create:
            model.createPlaylist(name: name.trimmingCharacters(in: .whitespaces),
                                 description: description,
                                 trackIds: Array(selectedIds))
        case .rename:
            if let id = sheet.playlist?.id {
                model.renamePlaylist(id: id, name: name.trimmingCharacters(in: .whitespaces))
            }
        case .edit:
            if let id = sheet.playlist?.id {
                model.updatePlaylistTracks(id: id, trackIds: Array(selectedIds))
            }
        }
        dismiss()
    }
}
