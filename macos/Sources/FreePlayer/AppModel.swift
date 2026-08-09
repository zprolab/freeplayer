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

/// Accumulates only intervals in which audio is actively playing.
struct PlaybackSessionClock {
    private(set) var accumulated: TimeInterval = 0
    private var resumedAt: Date?

    mutating func start(at date: Date = Date()) {
        accumulated = 0
        resumedAt = date
    }

    mutating func pause(at date: Date = Date()) {
        guard let resumedAt else { return }
        accumulated += max(0, date.timeIntervalSince(resumedAt))
        self.resumedAt = nil
    }

    mutating func resume(at date: Date = Date()) {
        guard resumedAt == nil else { return }
        resumedAt = date
    }

    mutating func finish(at date: Date = Date()) -> TimeInterval {
        pause(at: date)
        let elapsed = accumulated
        reset()
        return elapsed
    }

    mutating func reset() {
        accumulated = 0
        resumedAt = nil
    }
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
    @Published var autoFetchMeta = false
    @Published var lyricsFetchState: MetadataFetchState = .idle
    @Published var coverFetchState: MetadataFetchState = .idle
    @Published var metadataBackfillProgress: MetadataBackfillProgress?
    @Published var metadataRevision = 0

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
    private let metadataFetcher = MetadataFetchService.shared

    private var playSessionId: Int64?
    private var playClock = PlaybackSessionClock()
    private var timeTimer: Timer?
    private var autoMetadataAttempts: Set<Int64> = []
    private var metadataBackfillRunning = false

    var displayedTracks: [Track] {
        activePlaylistId == nil ? tracks : playlistTracks
    }

    // MARK: Bootstrap

    func start() {
        _ = Database.shared.open(path: Database.defaultDbPath())
        TrayController.shared.onPlayPause = { [weak self] in self?.togglePlayPause() }
        TrayController.shared.onNext = { [weak self] in self?.next() }
        TrayController.shared.onPrevious = { [weak self] in self?.previous() }
        TrayController.shared.onShowWindow = { [weak self] in self?.showWindow() }
        TrayController.shared.create()
        checkSetup()
        loadPlaylists()
        timeTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
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
        autoFetchMeta = Database.shared.getBoolSetting("auto_fetch_meta", fallback: false)

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
        lyricsFetchState = .idle
        coverFetchState = .idle
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
            startAutomaticMetadataFetch(for: track)
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
            playClock.pause()
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
            playClock.resume()
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
        playClock.start()
    }

    private func endPlaySession() {
        guard let sid = playSessionId else {
            playSessionId = nil
            playClock.reset()
            return
        }
        let elapsed = playClock.finish()
        let percentage = duration > 0 ? min((elapsed / duration) * 100, 100) : 0
        Database.shared.endPlaySession(sessionId: sid,
                                       durationSeconds: elapsed.rounded(),
                                       playPercentage: percentage.rounded())
        playSessionId = nil
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

    func setAutoFetchMeta(_ enabled: Bool) {
        autoFetchMeta = enabled
        Database.shared.setSetting("auto_fetch_meta", enabled ? "true" : "false")
        if enabled, let track = currentTrack {
            startAutomaticMetadataFetch(for: track)
        }
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
        playClock.reset()
        libraryDir = ""
        isSetup = false
        importMode = .copy
        defaultVolume = 0.8
        defaultVisualizer = .waveform
        visualizerMode = .waveform
        autoFetchMeta = false
        autoMetadataAttempts = []
        metadataBackfillProgress = nil
        metadataBackfillRunning = false
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
        if currentTrack?.id == track.id {
            endPlaySession()
            engine.stop()
            currentTrack = nil
            isPlaying = false
            currentTime = 0
            duration = 0
            TrayController.shared.clearNowPlaying()
        }
        _ = Database.shared.deleteTrack(id: track.id)
        queue.removeAll { $0.id == track.id }
        shuffledQueue.removeAll { $0.id == track.id }
        if let currentTrack {
            queueIndex = queue.firstIndex { $0.id == currentTrack.id } ?? -1
        } else {
            queueIndex = -1
        }
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
        updateTrackMetadataInMemory(trackId: track.id, lrcPath: target)
        metadataRevision += 1
    }

    func removeLrc(for track: Track) {
        Database.shared.setTrackLrc(trackId: track.id, lrcPath: nil)
        if let idx = tracks.firstIndex(where: { $0.id == track.id }) {
            tracks[idx].lrcPath = nil
        }
        updateTrackMetadataInMemory(trackId: track.id, lrcPath: nil)
        metadataRevision += 1
    }

    // ── Remote metadata ──

    @discardableResult
    func fetchLyrics(for track: Track, reportState: Bool = true) async -> Bool {
        if reportState { lyricsFetchState = .fetching }
        guard let content = await metadataFetcher.fetchLyrics(for: track),
              saveFetchedLyrics(content, for: track) else {
            if reportState, currentTrack?.id == track.id { lyricsFetchState = .notFound }
            return false
        }
        if reportState, currentTrack?.id == track.id { lyricsFetchState = .idle }
        return true
    }

    @discardableResult
    func fetchCover(for track: Track, reportState: Bool = true) async -> Bool {
        if reportState { coverFetchState = .fetching }
        guard let data = await metadataFetcher.fetchCover(for: track),
              NSImage(data: data) != nil,
              saveFetchedCover(data, for: track) else {
            if reportState, currentTrack?.id == track.id { coverFetchState = .notFound }
            return false
        }
        if reportState, currentTrack?.id == track.id { coverFetchState = .idle }
        return true
    }

    func startMetadataBackfill() {
        guard !metadataBackfillRunning, !tracks.isEmpty else { return }
        metadataBackfillRunning = true
        let snapshot = tracks
        metadataBackfillProgress = MetadataBackfillProgress(done: 0, total: snapshot.count, saved: 0, failed: 0, noMatch: 0)
        Task { [weak self] in
            guard let self else { return }
            var progress = MetadataBackfillProgress(done: 0, total: snapshot.count, saved: 0, failed: 0, noMatch: 0)
            for track in snapshot {
                var missing = false
                var saved = false
                if track.coverPath == nil || !(track.coverPath.map(FileManager.default.fileExists(atPath:)) ?? false) {
                    missing = true
                    if await self.fetchCover(for: track, reportState: false) {
                        saved = true
                        progress.saved += 1
                    }
                }
                if self.lrcContent(for: track) == nil {
                    missing = true
                    if await self.fetchLyrics(for: track, reportState: false) {
                        saved = true
                        progress.saved += 1
                    }
                }
                if missing && !saved { progress.noMatch += 1 }
                progress.done += 1
                self.metadataBackfillProgress = progress
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
            self.metadataBackfillRunning = false
            self.metadataBackfillProgress = nil
        }
    }

    private func startAutomaticMetadataFetch(for track: Track) {
        guard autoFetchMeta, !autoMetadataAttempts.contains(track.id) else { return }
        autoMetadataAttempts.insert(track.id)
        Task { [weak self] in
            guard let self else { return }
            if track.coverPath == nil || !(track.coverPath.map(FileManager.default.fileExists(atPath:)) ?? false) {
                _ = await self.fetchCover(for: track, reportState: false)
            }
            guard self.autoFetchMeta else { return }
            if self.lrcContent(for: track) == nil {
                _ = await self.fetchLyrics(for: track, reportState: false)
            }
        }
    }

    private func saveFetchedLyrics(_ content: String, for track: Track) -> Bool {
        let source = URL(fileURLWithPath: track.filePath)
        let stem = MetadataExtractor.cleanStem(source.deletingPathExtension().lastPathComponent)
        let target = source.deletingLastPathComponent().appendingPathComponent("\(stem).\(track.id).lrc")
        do {
            try content.write(to: target, atomically: true, encoding: .utf8)
            Database.shared.setTrackLrc(trackId: track.id, lrcPath: target.path)
            updateTrackMetadataInMemory(trackId: track.id, lrcPath: target.path)
            metadataRevision += 1
            return true
        } catch {
            NSLog("[metadata] failed to save lyrics: %@", error.localizedDescription)
            return false
        }
    }

    private func saveFetchedCover(_ data: Data, for track: Track) -> Bool {
        let audioURL = URL(fileURLWithPath: track.filePath)
        let directory = audioURL.deletingLastPathComponent().appendingPathComponent(".covers", isDirectory: true)
        let target = directory.appendingPathComponent("cover-\(track.id).jpg")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: target, options: .atomic)
            Database.shared.setTrackCover(trackId: track.id, coverPath: target.path)
            CoverCache.shared.clear()
            updateTrackMetadataInMemory(trackId: track.id, coverPath: target.path)
            metadataRevision += 1
            return true
        } catch {
            NSLog("[metadata] failed to save cover: %@", error.localizedDescription)
            return false
        }
    }

    private func updateTrackMetadataInMemory(trackId: Int64, coverPath: String? = nil, lrcPath: String? = nil) {
        func update(_ track: inout Track) {
            if let coverPath { track.coverPath = coverPath }
            if lrcPath != nil || Database.shared.trackLrc(trackId: trackId) == nil { track.lrcPath = lrcPath }
        }
        if let index = tracks.firstIndex(where: { $0.id == trackId }) { update(&tracks[index]) }
        if let index = playlistTracks.firstIndex(where: { $0.id == trackId }) { update(&playlistTracks[index]) }
        if let index = queue.firstIndex(where: { $0.id == trackId }) { update(&queue[index]) }
        if let index = shuffledQueue.firstIndex(where: { $0.id == trackId }) { update(&shuffledQueue[index]) }
        if currentTrack?.id == trackId, var fresh = currentTrack {
            update(&fresh)
            currentTrack = fresh
        }
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
