import SwiftUI

/// Edit track metadata sheet (Cmd+Enter to save).
struct EditTrackSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let track: Track

    @State private var title: String
    @State private var artist: String
    @State private var album: String
    @State private var genre: String
    @State private var year: String
    @State private var error: String?

    init(track: Track) {
        self.track = track
        _title = State(initialValue: track.title)
        _artist = State(initialValue: track.artist)
        _album = State(initialValue: track.album)
        _genre = State(initialValue: track.genre ?? "")
        _year = State(initialValue: track.year.map(String.init) ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Track")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
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

            VStack(spacing: 12) {
                if let error {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.danger)
                }
                field("Title") {
                    TextField("Track title", text: $title)
                        .textFieldStyle(.roundedBorder)
                }
                field("Artist") {
                    TextField("Artist name", text: $artist)
                        .textFieldStyle(.roundedBorder)
                }
                field("Album") {
                    TextField("Album name", text: $album)
                        .textFieldStyle(.roundedBorder)
                }
                HStack(spacing: 12) {
                    field("Genre") {
                        TextField("Genre", text: $genre)
                            .textFieldStyle(.roundedBorder)
                    }
                    field("Year") {
                        TextField("Year", text: $year)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: year) { newValue in
                                let filtered = newValue.filter { $0.isNumber }
                                if let v = Int(filtered) {
                                    year = String(min(v, 2099))
                                } else {
                                    year = filtered
                                }
                            }
                    }
                }
            }
            .padding(14)

            Divider()

            HStack {
                Text("⌘↵ to save")
                    .font(Theme.mono)
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Button {
                    save()
                } label: {
                    Text("Save")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }
            .padding(14)
        }
        .frame(width: 480)
        .background(Theme.background)
        .onSubmit(of: .text) {
            if NSApp.currentEvent?.modifierFlags.contains(.command) == true {
                save()
            }
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

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            error = "Title cannot be empty"
            return
        }
        let y = year.isEmpty ? nil : Int(year)
        model.saveTrackEdits(id: track.id,
                             title: trimmed,
                             artist: artist.trimmingCharacters(in: .whitespaces),
                             album: album.trimmingCharacters(in: .whitespaces),
                             genre: genre.trimmingCharacters(in: .whitespaces),
                             year: y)
        dismiss()
    }
}
