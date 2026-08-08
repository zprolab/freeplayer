import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                SidebarView()
                    .frame(width: 220)
                MainContent()
                    .frame(minWidth: 620)
            }
            PlayerBarView()
                .frame(height: 72)
        }
        .background(Theme.sidebarBg)
        .onAppear {
            if let window = NSApp.windows.first(where: { !$0.isVisible || $0.title.isEmpty }) {
                (NSApp.delegate as? AppDelegate)?.configure(window: window)
            }
        }
        .sheet(isPresented: $model.importSheetPresented, onDismiss: {
            model.importInitialPaths = nil
        }) {
            ImportSheet()
        }
        .sheet(item: $model.playlistSheet) { sheet in
            PlaylistSheet(sheet: sheet)
        }
        .sheet(item: $model.editTrack) { track in
            EditTrackSheet(track: track)
        }
    }
}

struct MainContent: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TopBar()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.background)
        .overlay {
            if model.dragOver && model.view == .library && !model.importSheetPresented {
                DropToImportOverlay()
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $model.dragOver) { providers in
            guard model.view == .library else { return false }
            model.handleDroppedProviders(providers)
            return true
        }
    }

    /// Full-area "Drop to Import" zone shown while dragging files over the library.
    private struct DropToImportOverlay: View {
        @EnvironmentObject private var model: AppModel

        var body: some View {
            ZStack {
                Color.black.opacity(0.45)
                VStack(spacing: 14) {
                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(.white)
                    Text("Drop to Import")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Audio files and folders supported")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .frame(maxWidth: 280, maxHeight: 140)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.accent.opacity(0.85)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [6])))
            }
            .ignoresSafeArea()
            .transition(.opacity)
        }
    }

    @ViewBuilder private var content: some View {
        if model.isLoading {
            VStack(spacing: 12) {
                ProgressView().controlSize(.large)
                Text("Loading FreePlayer...").foregroundStyle(Theme.textSecondary)
            }
        } else {
            switch model.view {
            case .library:
                if !model.isSetup {
                    welcomeState
                } else {
                    LibraryView()
                }
            case .nowPlaying:
                NowPlayingView()
            case .stats:
                StatsView()
            case .settings:
                SettingsView()
            @unknown default:
                SettingsView()
            }
        }
    }

    private var welcomeState: some View {
        VStack(spacing: 14) {
            Image(systemName: "music.note")
                .font(.system(size: 60))
                .foregroundStyle(Theme.textTertiary)
            Text("Welcome to FreePlayer")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text("Set up your music library to get started. Choose a directory where your music will be stored, then import your audio files.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button {
                model.importSheetPresented = true
            } label: {
                Text("Set Up Library")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct TopBar: View {
    @EnvironmentObject private var model: AppModel

    private var title: String {
        switch model.view {
        case .library:
            if let id = model.activePlaylistId,
               let pl = model.playlists.first(where: { $0.id == id }) {
                return pl.name
            }
            return "Library"
        case .nowPlaying: return "Now Playing"
        case .stats: return "Statistics"
        case .settings: return "Settings"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            if model.view == .library {
                Text("\(model.displayedTracks.count) tracks")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Theme.blue.opacity(0.08)))
            }
            Spacer()
            if model.view == .library {
                SearchField(query: $model.searchQuery)
                    .onChange(of: model.searchQuery) { newValue in
                        model.applySearch(query: newValue)
                    }
                Button {
                    model.importSheetPresented = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text("Import")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.background)
    }
}

private struct SearchField: View {
    @Binding var query: String

    var body: some View {
        HStack(spacing: 6) {
            // Custom magnifying glass SVG (matches original)
            Image(nsImage: searchIcon)
                .resizable()
                .frame(width: 14, height: 14)
                .foregroundStyle(Theme.textTertiary)
            TextField("Search your library...", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(width: 240, height: 32)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border))
    }

    /// Renders the original SVG magnifying glass icon into an NSImage.
    private var searchIcon: NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath()
            // Outer circle
            path.appendArc(withCenter: NSPoint(x: 7, y: 9), radius: 5.5,
                          startAngle: 0, endAngle: 360)
            // Handle line
            path.move(to: NSPoint(x: 11.3, y: 13.3))
            path.line(to: NSPoint(x: 15, y: 17))
            path.lineWidth = 1.6
            path.lineCapStyle = .round
            NSColor.secondaryLabelColor.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
