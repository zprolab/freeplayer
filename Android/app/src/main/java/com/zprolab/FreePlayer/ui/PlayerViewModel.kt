package com.zprolab.FreePlayer.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.zprolab.FreePlayer.data.Database
import com.zprolab.FreePlayer.data.ListeningStats
import com.zprolab.FreePlayer.data.PlayHistoryEntry
import com.zprolab.FreePlayer.data.Playlist
import com.zprolab.FreePlayer.data.Track
import com.zprolab.FreePlayer.import.ImportManager
import com.zprolab.FreePlayer.playback.PlayerController
import com.zprolab.FreePlayer.playback.QueueLogic
import com.zprolab.FreePlayer.util.LrcLine
import kotlinx.coroutines.Job
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

class PlayerViewModel(app: Application) : AndroidViewModel(app) {

    val state: StateFlow<com.zprolab.FreePlayer.playback.PlayerUiState> = PlayerController.state

    private val db get() = PlayerController.db
    private var searchJob: Job? = null
    private var tickerJob: Job? = null

    init {
        PlayerController.init(app)
        checkSetup()
        startTicker()
    }

    // ── setup / tracks ──

    fun checkSetup() {
        viewModelScope.launch(Dispatchers.IO) {
            val libraryDir = db.getSetting("library_dir", null)
            PlayerController.updateState {
                it.copy(isSetup = libraryDir != null, libraryDir = libraryDir ?: "")
            }
            val impMode = db.getSetting("import_mode", null)
            if (impMode != null) {
                // SAF content URIs cannot be retained as reliable symlink targets.
                // Migrate prior desktop-style settings to Android's copy mode.
                val mode = "copy"
                if (mode != impMode) db.setSetting("import_mode", mode)
                PlayerController.updateState { it.copy(importMode = mode) }
            }
            // volume restore: saved volume, else default_volume, else 0.8
            val savedVol = db.getSetting("volume", null) ?: db.getSetting("default_volume", null)
            if (savedVol != null) {
                val vol = savedVol.toFloatOrNull()
                if (vol != null && vol.isFinite()) {
                    PlayerController.updateState { it.copy(defaultVolume = vol, volume = vol) }
                }
            }
            val defVis = db.getSetting("default_visualizer", null)
            if (defVis != null) {
                PlayerController.updateState { it.copy(defaultVisualizer = defVis, visualizerMode = defVis) }
            }
            if (libraryDir != null) {
                loadTracks()
            }
            loadPlaylists()
            PlayerController.updateState { it.copy(isLoading = false) }
        }
    }

    fun loadTracks() {
        viewModelScope.launch(Dispatchers.IO) {
            val s = state.value
            val tracks = db.getAllTracks(s.searchQuery, s.sortBy, s.sortDir)
            PlayerController.updateState { it.copy(tracks = tracks) }
        }
    }

    fun onSearchQueryChange(query: String) {
        PlayerController.updateState { it.copy(searchQuery = query) }
        searchJob?.cancel()
        searchJob = viewModelScope.launch(Dispatchers.IO) {
            delay(250)
            loadTracks()
        }
    }

    fun onSort(column: String) {
        val s = state.value
        PlayerController.updateState {
            if (s.sortBy == column) {
                it.copy(sortDir = if (s.sortDir == "ASC") "DESC" else "ASC")
            } else {
                it.copy(
                    sortBy = column,
                    sortDir = if (column == "title" || column == "artist") "ASC" else "DESC",
                )
            }
        }
        loadTracks()
    }

    fun onImportComplete() {
        PlayerController.updateState { it.copy(importModalOpen = false) }
        viewModelScope.launch(Dispatchers.IO) {
            val libraryDir = db.getSetting("library_dir", null)
            PlayerController.updateState { it.copy(isSetup = libraryDir != null, libraryDir = libraryDir ?: "") }
            loadTracks()
        }
    }

    fun onImportModeChange(mode: String) {
        PlayerController.updateState { it.copy(importMode = mode) }
        viewModelScope.launch(Dispatchers.IO) { db.setSetting("import_mode", mode) }
    }

    fun onDefaultVolumeChange(vol: Float) {
        PlayerController.updateState { it.copy(defaultVolume = vol) }
        viewModelScope.launch(Dispatchers.IO) { db.setSetting("default_volume", vol.toString()) }
    }

    fun onDefaultVisualizerChange(mode: String) {
        PlayerController.updateState { it.copy(defaultVisualizer = mode) }
        viewModelScope.launch(Dispatchers.IO) { db.setSetting("default_visualizer", mode) }
    }

    fun onResetDatabase() {
        viewModelScope.launch(Dispatchers.IO) {
            db.resetDatabase()
            PlayerController.updateState {
                it.copy(
                    tracks = emptyList(), currentTrack = null, isPlaying = false,
                    queue = emptyList(), queueIndex = -1, libraryDir = "", isSetup = false,
                    importMode = "copy", volume = 0.8f, defaultVolume = 0.8f, defaultVisualizer = "waveform",
                    visualizerMode = "waveform", playlists = emptyList(), activePlaylistId = null,
                    playlistTracks = emptyList(),
                )
            }
        }
    }

    fun onSelectLibraryDir() {
        // Library dir is app-owned on Android; path is fixed. Mirrors desktop
        // setting persistence so the UI stays consistent.
        viewModelScope.launch(Dispatchers.IO) {
            val dir = ImportManager.libraryDir(getApplication())
            db.setSetting("library_dir", dir)
            PlayerController.updateState { it.copy(libraryDir = dir, isSetup = true) }
            loadTracks()
        }
    }

    // ── playlists (mirrors usePlaylists) ──

    fun loadPlaylists() {
        viewModelScope.launch(Dispatchers.IO) {
            val playlists = db.getAllPlaylists()
            PlayerController.updateState { it.copy(playlists = playlists) }
        }
    }

    fun selectPlaylist(playlistId: Long?) {
        viewModelScope.launch(Dispatchers.IO) {
            PlayerController.updateState { it.copy(activePlaylistId = playlistId) }
            if (playlistId != null) {
                val tracks = db.getPlaylistTracks(playlistId)
                PlayerController.updateState { it.copy(playlistTracks = tracks) }
            }
            PlayerController.updateState { it.copy(view = com.zprolab.FreePlayer.playback.View.LIBRARY) }
        }
    }

    fun createPlaylist(name: String, description: String?, trackIds: List<Long>?) {
        viewModelScope.launch(Dispatchers.IO) {
            val playlistId = db.createPlaylist(name, description)
            val all = trackIds?.toMutableList() ?: mutableListOf()
            pendingAddTrack?.let { t -> if (!all.contains(t.id)) all.add(t.id) }
            pendingAddTrack = null
            if (all.isNotEmpty()) db.addTracksToPlaylist(playlistId, all)
            loadPlaylists()
        }
    }

    fun renamePlaylist(id: Long, name: String) {
        viewModelScope.launch(Dispatchers.IO) {
            db.renamePlaylist(id, name)
            loadPlaylists()
        }
    }

    fun updatePlaylistTracks(playlistId: Long, trackIds: List<Long>) {        viewModelScope.launch(Dispatchers.IO) {
            db.setPlaylistTracks(playlistId, trackIds)
            if (state.value.activePlaylistId == playlistId) {
                val tracks = db.getPlaylistTracks(playlistId)
                PlayerController.updateState { it.copy(playlistTracks = tracks) }
            }
            loadPlaylists()
        }
    }

    /** Existing track ids of a playlist — used by the edit modal to pre-select. */
    suspend fun loadPlaylistTrackIds(playlistId: Long): List<Long> =
        withContext(kotlinx.coroutines.Dispatchers.IO) {
            db.getPlaylistTracks(playlistId).map { it.id }
        }

    fun deletePlaylist(playlistId: Long) {
        viewModelScope.launch(Dispatchers.IO) {
            db.deletePlaylist(playlistId)
            if (state.value.activePlaylistId == playlistId) {
                PlayerController.updateState { it.copy(activePlaylistId = null) }
            }
            loadPlaylists()
        }
    }

    fun addToPlaylist(playlistId: Long, trackId: Long) {
        viewModelScope.launch(Dispatchers.IO) {
            db.addTrackToPlaylist(playlistId, trackId)
            if (state.value.activePlaylistId == playlistId) {
                val tracks = db.getPlaylistTracks(playlistId)
                PlayerController.updateState { it.copy(playlistTracks = tracks) }
            }
        }
    }

    fun removeFromPlaylist(trackId: Long) {
        viewModelScope.launch(Dispatchers.IO) {
            val pid = state.value.activePlaylistId ?: return@launch
            db.removeTrackFromPlaylist(pid, trackId)
            val tracks = db.getPlaylistTracks(pid)
            PlayerController.updateState { it.copy(playlistTracks = tracks) }
        }
    }

    fun deleteTrack(trackId: Long) {
        viewModelScope.launch(Dispatchers.IO) {
            db.deleteTrack(trackId)
            loadTracks()
            val pid = state.value.activePlaylistId
            if (pid != null) {
                val tracks = db.getPlaylistTracks(pid)
                PlayerController.updateState { it.copy(playlistTracks = tracks) }
            }
        }
    }

    // ── edit metadata ──

    fun updateTrackMetadata(trackId: Long, fields: Map<String, Any?>) {
        viewModelScope.launch(Dispatchers.IO) {
            db.updateTrack(trackId, fields)
            loadTracks()
            val pid = state.value.activePlaylistId
            if (pid != null) {
                val tracks = db.getPlaylistTracks(pid)
                PlayerController.updateState { it.copy(playlistTracks = tracks) }
            }
        }
    }

    // ── lrc ──

    fun removeLrc(trackId: Long) {
        viewModelScope.launch(Dispatchers.IO) {
            db.setTrackLrc(trackId, null)
        }
    }

    // ── stats ──

    fun getStats(onResult: (ListeningStats) -> Unit) {
        viewModelScope.launch(Dispatchers.IO) {
            val stats = db.getListeningStats()
            withContext(Dispatchers.Main) { onResult(stats) }
        }
    }

    fun getPlayHistory(limit: Int, onResult: (List<PlayHistoryEntry>) -> Unit) {
        viewModelScope.launch(Dispatchers.IO) {
            val history = db.getPlayHistory(limit)
            withContext(Dispatchers.Main) { onResult(history) }
        }
    }

    // ── pending add track (right-click -> create playlist) ──

    var pendingAddTrack: Track? = null

    var pendingLrcTrack: Track? = null

    // ── view / modal helpers ──

    fun updateView(view: com.zprolab.FreePlayer.playback.View) {
        PlayerController.updateState { it.copy(view = view) }
    }

    fun openImportModal() {
        PlayerController.updateState { it.copy(importModalOpen = true) }
    }

    fun closeImportModal() {
        PlayerController.updateState { it.copy(importModalOpen = false) }
    }

    fun setVisualizerMode(mode: String) {
        PlayerController.updateState { it.copy(visualizerMode = mode) }
    }

    // ── lyrics ──

    /**
     * Load lyrics for a track: DB lrc_path first, then sidecar detection
     * next to the audio file. Encoding fallback chain UTF-8 -> GB18030 ->
     * Shift_JIS (plus Big5/EUC-KR) is handled by LrcParser.
     */
    suspend fun loadLyrics(track: Track?): List<LrcLine> {
        if (track == null) return emptyList()
        return withContext(kotlinx.coroutines.Dispatchers.IO) {
            var path = db.getTrackLrc(track.id)
            if (path == null) {
                path = com.zprolab.FreePlayer.metadata.MetadataExtractor.findSidecarLrc(track.filePath)
            }
            if (path == null) return@withContext emptyList()
            val file = File(path)
            if (!file.exists()) return@withContext emptyList()
            val raw = runCatching { file.readBytes() }.getOrNull() ?: return@withContext emptyList()
            val content = com.zprolab.FreePlayer.util.LrcParser.decodeLrc(raw)
            com.zprolab.FreePlayer.util.LrcParser.parse(content)
        }
    }

    /**
     * Copy a picked .lrc file next to the audio file (mirrors desktop upload),
     * persist the path, and re-parse.
     */
    fun uploadLrc(track: Track?, uri: android.net.Uri, onLoaded: (List<LrcLine>) -> Unit) {
        if (track == null) return
        viewModelScope.launch {
            withContext(kotlinx.coroutines.Dispatchers.IO) {
                val audioFile = File(track.filePath)
                val dir = audioFile.parentFile ?: return@withContext
                val name = uri.lastPathSegment?.substringAfterLast('/')?.substringBefore('?') ?: "lyrics.lrc"
                val target = File(dir, name)
                try {
                    getApplication<Application>().contentResolver.openInputStream(uri)?.use { input ->
                        target.outputStream().use { out -> input.copyTo(out) }
                    }
                    db.setTrackLrc(track.id, target.absolutePath)
                } catch (e: Exception) {
                }
            }
            onLoaded(loadLyrics(track))
        }
    }

    // ── time ticker ──

    private fun startTicker() {
        tickerJob = viewModelScope.launch {
            while (true) {
                delay(500)
                val player = PlayerController.getPlayer() ?: continue
                PlayerController.setCurrentTime(player.currentPosition / 1000.0)
                PlayerController.setDuration(player.duration.coerceAtLeast(0) / 1000.0)
            }
        }
    }

    override fun onCleared() {
        searchJob?.cancel()
        tickerJob?.cancel()
    }
}
