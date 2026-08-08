import Foundation
import AppKit
import Combine

// Sheet state for the playlist modal.
struct PlaylistSheetState: Identifiable {
    enum Mode { case create, rename, edit }
    var id = UUID()
    var mode: Mode
    var playlist: Playlist?
}

/// Central observable app state — the native mirror of the old React
/// PlayerContext + hooks (usePlayback / useLibrary / usePlaylists).
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    private init() {}

    // ── Navigation / library ──
    @Published var view: AppView = .library
    @Published var tracks: [Track] = []
    @Published var searchQuery = ""
    @Published var sortBy = "imported_at"
    @Published var sortDir = "DESC"
    @Published var isLoading = true
    @Published var isSetup = false
    @Published var libraryDir = ""

    // ── Playlists ──
    @Published var playlists: [Playlist] = []
    @Published var activePlaylistId: Int64?
    @Published var playlistTracks: [Track] = []

    // ── Playback ──
    @Published var currentTrack: Track?
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var volume: Double = 0.8
    @Published var playMode: PlayMode = .sequential
    @Published var queue: [Track] = []
    @Published var queueIndex: Int = -1
    private var shuffledQueue: [Track] = []

    // ── Settings ──
    @Published var importMode: ImportMode = .copy
    @Published var defaultVolume: Double = 0.8
    @Published var defaultVisualizer: VisualizerMode = .waveform
    @Published var visualizerMode: VisualizerMode = .waveform

    // ── UI transient state ──
    @Published var importSheetPresented = false
    @Published var importInitialPaths: [String]?
    @Published var playlistSheet: PlaylistSheetState?
    @Published var pendingAddTrack: Track?
    @Published var editTrack: Track?
    @Published var immersivePresented = false
    @Published var dragOver = false

    // ── Services ──
    let engine = AudioEngine()
    let analyzer = AudioAnalyzer()

    private var playSessionId: Int64?
    private var playStartTime: Date?
    private var timeTimer: Timer?

    var displayedTracks: [Track] {
        activePlaylistId == nil ? tracks : playlistTracks
    }

    // MARK: Bootstrap

    func start() {
        Database.shared.open(path: Database.defaultDbPath())
        TrayController.shared.onPlayPause = { [weak self] in self?.togglePlayPause() }
        TrayController.shared.onNext = { [weak self] in self?.next() }
        TrayController.shared.onPrevious = { [weak self] in self?.previous() }
        TrayController.shared.onShowWindow = { [weak self] in self?.showWindow() }
        TrayController.shared.create()
        checkSetup()
        loadPlaylists()
        timeTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
    }

    func onTerminate() {
        endPlaySession()
        Database.shared.close()
    }

    private func tick() {
        currentTime = engine.currentTime
        let d = engine.duration
        if isPlaying && d > 0 && currentTime >= d - 0.15 {
            next()
        }
    }

    // ── Library ──

    func loadTracks() {
        tracks = Database.shared.getAllTracks(search: searchQuery, sortBy: sortBy, sortDir: sortDir)
    }

    func checkSetup() {
        libraryDir = Database.shared.getSetting("library_dir", nil) ?? ""
        isSetup = !libraryDir.isEmpty

        importMode = ImportMode(rawValue: Database.shared.getSetting("import_mode", "copy") ?? "copy") ?? .copy

        let savedVol = Database.shared.getSetting("volume", nil)
        let defVol = savedVol ?? Database.shared.getSetting("default_volume", nil)
        if let volStr = defVol, let vol = Double(volStr) {
            defaultVolume = vol
            volume = vol
        }
        engine.setVolume(volume)

        if let vis = Database.shared.getSetting("default_visualizer", nil),
           let mode = VisualizerMode(rawValue: vis) {
            defaultVisualizer = mode
            visualizerMode = mode
        }

        if isSetup {
            loadTracks()
        }
        isLoading = false
    }

    func applySearch(query: String) {
        searchQuery = query
        // Debounce (250ms) like the web app
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard let self, self.searchQuery == query else { return }
            self.loadTracks()
        }
    }

    // ── Playback ──

    func play(track: Track, from list: [Track]) {
        queue = list
        queueIndex = list.firstIndex(where: { $0.id == track.id }) ?? 0
        if playMode == .shuffle {
            var shuffled = list.shuffled()
            if let clickedIdx = shuffled.firstIndex(where: { $0.id == track.id }), clickedIdx > 0 {
                shuffled.swapAt(0, clickedIdx)
            }
            shuffledQueue = shuffled
        }
        play(track: track)
    }

    private func play(track: Track) {
        endPlaySession()
        currentTrack = track
        currentTime = 0
        duration = track.duration
        TrayController.shared.setNowPlaying(track: track)

        do {
            try engine.load(url: URL(fileURLWithPath: track.filePath))
            engine.setGain(gainDb: track.replaygainGain)
            engine.setVolume(volume)
            try engine.play()
            isPlaying = true
            startPlaySession(trackId: track.id)
            TrayController.shared.setPlaying(true)
        } catch {
            NSLog("[playback] failed to play %@: %@", track.filePath, error.localizedDescription)
            isPlaying = false
        }
    }

    func togglePlayPause() {
        if currentTrack == nil {
            guard !tracks.isEmpty else { return }
            play(track: tracks[0], from: tracks)
            return
        }
        if engine.isPlaying {
            engine.pause()
            isPlaying = false
            TrayController.shared.setPlaying(false)
        } else {
            // Track ended naturally and tick() hasn't advanced yet — restart
            // instead of resuming a finished (silent) segment.
            let d = engine.duration
            if d > 0 && engine.currentTime >= d - 0.15 {
                seek(to: 0)
            }
            engine.resume()
            isPlaying = true
            TrayController.shared.setPlaying(true)
        }
    }

    func next() {
        guard !queue.isEmpty else { return }
        if playMode == .repeatOne {
            seek(to: 0)
            if !engine.isPlaying {
                try? engine.play()
                isPlaying = true
                TrayController.shared.setPlaying(true)
            }
            return
        }

        var nextIdx: Int
        if playMode == .shuffle {
            if shuffledQueue.isEmpty { shuffledQueue = queue.shuffled() }
            let shuffled = shuffledQueue
            let currentShuffledIdx = shuffled.firstIndex(where: { $0.id == queue[queueIndex].id })
            if let idx = currentShuffledIdx, idx < shuffled.count - 1 {
                nextIdx = queue.firstIndex(where: { $0.id == shuffled[idx + 1].id }) ?? queueIndex
            } else {
                shuffledQueue = queue.shuffled()
                nextIdx = queue.firstIndex(where: { $0.id == shuffledQueue[0].id }) ?? 0
            }
        } else {
            nextIdx = queueIndex < queue.count - 1 ? queueIndex + 1 : 0
        }
        queueIndex = nextIdx
        play(track: queue[nextIdx])
    }

    func previous() {
        guard !queue.isEmpty else { return }
        if engine.currentTime > 3 {
            seek(to: 0)
            return
        }
        var prevIdx: Int
        if playMode == .shuffle {
            if shuffledQueue.isEmpty { shuffledQueue = queue.shuffled() }
            let shuffled = shuffledQueue
            let currentShuffledIdx = shuffled.firstIndex(where: { $0.id == queue[queueIndex].id })
            if let idx = currentShuffledIdx, idx > 0 {
                prevIdx = queue.firstIndex(where: { $0.id == shuffled[idx - 1].id }) ?? queueIndex
            } else if let last = shuffled.last {
                prevIdx = queue.firstIndex(where: { $0.id == last.id }) ?? queueIndex
            } else {
                prevIdx = queueIndex
            }
        } else {
            prevIdx = queueIndex > 0 ? queueIndex - 1 : queue.count - 1
        }
        queueIndex = prevIdx
        play(track: queue[prevIdx])
    }

    func seek(to time: Double) {
        engine.seek(to: time)
        currentTime = time
    }

    func setVolume(_ vol: Double) {
        volume = vol
        engine.setVolume(vol)
        Database.shared.setSetting("volume", String(vol))
    }

    func setPlayMode(_ mode: PlayMode) {
        playMode = mode
        if mode == .shuffle && !shuffledQueue.isEmpty {
            // keep existing shuffle
        } else if mode == .shuffle {
            shuffledQueue = queue.shuffled()
        } else {
            shuffledQueue = []
        }
    }

    // ── Play sessions (listening stats) ──

    private func startPlaySession(trackId: Int64) {
        endPlaySession()
        playSessionId = Database.shared.startPlaySession(trackId: trackId)
        playStartTime = Date()
    }

    private func endPlaySession() {
        guard let sid = playSessionId, let start = playStartTime else {
            playSessionId = nil
            playStartTime = nil
            return
        }
        let elapsed = Date().timeIntervalSince(start)
        let percentage = duration > 0 ? min((elapsed / duration) * 100, 100) : 0
        Database.shared.endPlaySession(sessionId: sid,
                                       durationSeconds: elapsed.rounded(),
                                       playPercentage: percentage.rounded())
        playSessionId = nil
        playStartTime = nil
    }

    // ── Settings actions ──

    func setImportMode(_ mode: ImportMode) {
        importMode = mode
        Database.shared.setSetting("import_mode", mode.rawValue)
    }

    func setDefaultVolume(_ vol: Double) {
        defaultVolume = vol
        Database.shared.setSetting("default_volume", String(vol))
    }

    func setDefaultVisualizer(_ mode: VisualizerMode) {
        defaultVisualizer = mode
        Database.shared.setSetting("default_visualizer", mode.rawValue)
    }

    func selectLibraryDir() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.title = "Select Library Directory"
        if panel.runModal() == .OK, let url = panel.url {
            libraryDir = url.path
            Database.shared.setSetting("library_dir", url.path)
            isSetup = true
            loadTracks()
        }
    }

    func resetDatabase() {
        _ = Database.shared.resetDatabase()
        tracks = []
        playlists = []
        activePlaylistId = nil
        playlistTracks = []
        currentTrack = nil
        isPlaying = false
        engine.stop()
        queue = []
        queueIndex = -1
        shuffledQueue = []
        currentTime = 0
        duration = 0
        playSessionId = nil
        playStartTime = nil
        libraryDir = ""
        isSetup = false
        importMode = .copy
        defaultVolume = 0.8
        defaultVisualizer = .waveform
        visualizerMode = .waveform
    }

    // ── Track editing ──

    func saveTrackEdits(id: Int64, title: String, artist: String, album: String, genre: String?, year: Int?) {
        var fields: [String: Any] = [
            "title": title,
            "artist": artist.isEmpty ? Track.unknownArtist : artist,
            "album": album.isEmpty ? Track.unknownAlbum : album,
        ]
        if let genre {
            let g = genre.trimmingCharacters(in: .whitespaces)
            fields["genre"] = g.isEmpty ? NSNull() : g
        } else {
            fields["genre"] = NSNull()
        }
        if let year {
            fields["year"] = year
        } else {
            fields["year"] = NSNull()
        }
        _ = Database.shared.updateTrack(id: id, fields: fields)
        editTrack = nil
        refreshAfterMutation()
    }

    func deleteTrack(_ track: Track) {
        _ = Database.shared.deleteTrack(id: track.id)
        if activePlaylistId == nil {
            refreshAfterMutation()
        } else {
            loadPlaylistTracks(id: activePlaylistId!)
        }
    }

    private func refreshAfterMutation() {
        loadTracks()
        if currentTrack != nil, let fresh = Database.shared.getTrack(id: currentTrack!.id) {
            currentTrack = fresh
        }
    }

    // ── LRC ──

    func lrcContent(for track: Track?) -> String? {
        guard let track else { return nil }
        var path = Database.shared.trackLrc(trackId: track.id)
        if path == nil {
            path = MetadataExtractor.findSidecarLrc(forAudioPath: track.filePath)
        }
        guard let path, FileManager.default.fileExists(atPath: path) else { return nil }
        return LRC.read(path: path)
    }

    func uploadLrc(for track: Track) {
        let panel = NSOpenPanel()
        panel.title = "Select LRC Lyrics File"
        panel.allowedContentTypes = [.init(filenameExtension: "lrc")!].compactMap { $0 }
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let chosen = panel.url else { return }

        let audioPath = track.filePath
        let target = (audioPath as NSString).deletingLastPathComponent + "/" + chosen.lastPathComponent
        if let data = try? Data(contentsOf: chosen) {
            try? data.write(to: URL(fileURLWithPath: target), options: .atomic)
        }
        Database.shared.setTrackLrc(trackId: track.id, lrcPath: target)
        if let idx = tracks.firstIndex(where: { $0.id == track.id }) {
            tracks[idx].lrcPath = target
        }
        objectWillChange.send()
    }

    func removeLrc(for track: Track) {
        Database.shared.setTrackLrc(trackId: track.id, lrcPath: nil)
        if let idx = tracks.firstIndex(where: { $0.id == track.id }) {
            tracks[idx].lrcPath = nil
        }
        objectWillChange.send()
    }

    // ── Playlists ──

    func loadPlaylists() {
        playlists = Database.shared.allPlaylists()
    }

    func selectPlaylist(_ id: Int64?) {
        activePlaylistId = id
        if let id {
            loadPlaylistTracks(id: id)
        } else {
            playlistTracks = []
        }
        view = .library
    }

    private func loadPlaylistTracks(id: Int64) {
        playlistTracks = Database.shared.playlistTracks(playlistId: id)
    }

    func createPlaylist(name: String, description: String, trackIds: [Int64]) {
        let id = Database.shared.createPlaylist(name: name, description: description.isEmpty ? nil : description)
        var ids = trackIds
        if let pending = pendingAddTrack, !ids.contains(pending.id) {
            ids.append(pending.id)
        }
        if !ids.isEmpty {
            Database.shared.addTracksToPlaylist(playlistId: id, trackIds: ids)
        }
        loadPlaylists()
        playlistSheet = nil
        pendingAddTrack = nil
    }

    func renamePlaylist(id: Int64, name: String) {
        _ = Database.shared.renamePlaylist(id: id, name: name)
        loadPlaylists()
        playlistSheet = nil
    }

    func updatePlaylistTracks(id: Int64, trackIds: [Int64]) {
        Database.shared.setPlaylistTracks(playlistId: id, trackIds: trackIds)
        if activePlaylistId == id {
            loadPlaylistTracks(id: id)
        }
        loadPlaylists()
        playlistSheet = nil
    }

    func deletePlaylist(id: Int64) {
        _ = Database.shared.deletePlaylist(id: id)
        if activePlaylistId == id {
            activePlaylistId = nil
            playlistTracks = []
        }
        loadPlaylists()
    }

    func addToPlaylist(playlistId: Int64, trackId: Int64) {
        _ = Database.shared.addTrackToPlaylist(playlistId: playlistId, trackId: trackId)
        if activePlaylistId == playlistId {
            loadPlaylistTracks(id: playlistId)
        }
    }

    func removeFromPlaylist(trackId: Int64) {
        guard let pid = activePlaylistId else { return }
        _ = Database.shared.removeTrackFromPlaylist(playlistId: pid, trackId: trackId)
        loadPlaylistTracks(id: pid)
    }

    // ── Tray settings ──

    func setTrayEnabled(_ enabled: Bool) {
        Database.shared.setSetting("tray_enabled", enabled ? "true" : "false")
    }

    func setTrayNotify(_ enabled: Bool) {
        Database.shared.setSetting("tray_notify", enabled ? "true" : "false")
    }

    func setStartOnBoot(_ enabled: Bool) {
        Database.shared.setSetting("start_on_boot", enabled ? "true" : "false")
        _ = TrayController.shared.setLoginItem(enabled: enabled)
    }

    // ── Drag & drop import ──

    /// Collects file URLs from dropped providers and opens the import sheet.
    func handleDroppedProviders(_ providers: [NSItemProvider]) {
        var paths: [String] = []
        let lock = NSLock()
        let group = DispatchGroup()
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                group.enter()
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                    defer { group.leave() }
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    lock.lock()
                    paths.append(url.path)
                    lock.unlock()
                }
            }
        }
        group.notify(queue: .main) {
            if !paths.isEmpty {
                self.importInitialPaths = paths
                self.importSheetPresented = true
            }
        }
    }
}
