package com.zprolab.FreePlayer.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.KeyEvent
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.zprolab.FreePlayer.audio.VisualizerEngine
import com.zprolab.FreePlayer.data.Playlist
import com.zprolab.FreePlayer.data.Track
import com.zprolab.FreePlayer.playback.PlayerController
import com.zprolab.FreePlayer.playback.View
import com.zprolab.FreePlayer.ui.components.EditModal
import com.zprolab.FreePlayer.ui.components.ImportModal
import com.zprolab.FreePlayer.ui.components.LibraryScreen
import com.zprolab.FreePlayer.ui.components.NowPlayingScreen
import com.zprolab.FreePlayer.ui.components.PlayerBar
import com.zprolab.FreePlayer.ui.components.PlaylistModal
import com.zprolab.FreePlayer.ui.components.SettingsScreen
import com.zprolab.FreePlayer.ui.components.Sidebar
import com.zprolab.FreePlayer.ui.components.StatsScreen
import com.zprolab.FreePlayer.ui.theme.Fp
import com.zprolab.FreePlayer.util.LrcLine
import com.zprolab.FreePlayer.util.LrcParser
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
@Composable
fun MainScreen(
    modifier: Modifier = Modifier,
    vm: PlayerViewModel = viewModel(),
) {
    val state by PlayerController.state.collectAsState()
    val visualizerEngine = remember { VisualizerEngine() }

    // Global keyboard shortcuts (App.jsx): Space toggles play/pause,
    // V toggles visualizer, Shift+V cycles modes. Handled via root
    // onKeyEvent so focused TextFields consume their own keys first
    // (space/v still typeable in search/edit boxes).
    val focusRequester = remember { androidx.compose.ui.focus.FocusRequester() }
    var shiftDown by remember { mutableStateOf(false) }
    val modes = listOf("waveform", "spectrogram", "off")
    val handleGlobalKey: (androidx.compose.ui.input.key.KeyEvent) -> Boolean = { event ->
        when (event.key) {
            androidx.compose.ui.input.key.Key.Spacebar -> {
                if (event.type == androidx.compose.ui.input.key.KeyEventType.KeyUp) {
                    PlayerController.togglePlayPause()
                }
                true
            }
            androidx.compose.ui.input.key.Key.V -> {
                if (event.type == androidx.compose.ui.input.key.KeyEventType.KeyUp) {
                    val s = PlayerController.state.value
                    if (shiftDown) {
                        val idx = modes.indexOf(s.visualizerMode)
                        PlayerController.updateState { it.copy(visualizerMode = modes[(idx + 1) % modes.size]) }
                    } else {
                        PlayerController.updateState {
                            it.copy(visualizerMode = if (s.visualizerMode == "off") "waveform" else "off")
                        }
                    }
                }
                true
            }
            androidx.compose.ui.input.key.Key.Escape -> {
                if (event.type == androidx.compose.ui.input.key.KeyEventType.KeyUp &&
                    PlayerController.state.value.isImmersive
                ) {
                    PlayerController.updateState { it.copy(isImmersive = false) }
                }
                true
            }
            androidx.compose.ui.input.key.Key.ShiftLeft, androidx.compose.ui.input.key.Key.ShiftRight -> {
                shiftDown = event.type == androidx.compose.ui.input.key.KeyEventType.KeyDown
                true
            }
            else -> false
        }
    }
    LaunchedEffect(Unit) { focusRequester.requestFocus() }

    // Release the Visualizer when the composition is disposed
    // (activity recreation) so the native session is freed.
    DisposableEffect(Unit) {
        onDispose { visualizerEngine.release() }
    }

    // Stretchable sidebar: width in dp (120..320), collapsible to icon rail.
    // On narrow screens (phones) it starts collapsed so the content area
    // stays wide; on tablets/desktop it starts expanded.
    val screenWidthDp = androidx.compose.ui.platform.LocalConfiguration.current.screenWidthDp
    var sidebarWidth by rememberSaveable { mutableStateOf(220f) }
    var sidebarCollapsed by rememberSaveable { mutableStateOf(screenWidthDp < 480) }

    var playlistModalMode by remember { mutableStateOf<String?>(null) }
    var playlistModalPlaylist by remember { mutableStateOf<Playlist?>(null) }
    var editingTrack by remember { mutableStateOf<Track?>(null) }

    var lyrics by remember { mutableStateOf<List<LrcLine>>(emptyList()) }

    // Load lyrics when the current track changes
    LaunchedEffect(state.currentTrack?.id) {
        lyrics = vm.loadLyrics(state.currentTrack)
    }

    // Attach visualizer to the player's audio session
    LaunchedEffect(state.isPlaying, state.currentTrack?.id) {
        if (state.isPlaying) {
            val player = PlayerController.getPlayer()
            if (player != null) {
                visualizerEngine.attach(player.audioSessionId)
            }
        }
    }

    // Upload .lrc flow
    val lrcPicker = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        val track = vm.pendingLrcTrack ?: state.currentTrack
        if (uri != null) {
            vm.uploadLrc(track, uri) { lines -> lyrics = lines }
        }
    }

    Box(modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().background(Fp.ContentBg)
        .focusRequester(focusRequester).focusable().onKeyEvent(handleGlobalKey)) {
        Row(Modifier.fillMaxSize()) {
            Sidebar(
                currentView = state.view,
                trackCount = state.tracks.size,
                playlists = state.playlists,
                activePlaylistId = state.activePlaylistId,
                width = sidebarWidth,
                collapsed = sidebarCollapsed,
                onToggleCollapsed = { sidebarCollapsed = !sidebarCollapsed },
                onResize = { sidebarWidth = it },
                onNavigate = { vm.updateView(it) },
                onImport = { vm.openImportModal() },
                onSelectPlaylist = { vm.selectPlaylist(it) },
                onCreatePlaylist = {
                    playlistModalMode = "create"
                    playlistModalPlaylist = null
                },
                onRenamePlaylist = {
                    playlistModalMode = "rename"
                    playlistModalPlaylist = it
                },
                onEditPlaylist = {
                    playlistModalMode = "edit"
                    playlistModalPlaylist = it
                },
                onDeletePlaylist = { vm.deletePlaylist(it.id) },
            )

            Column(Modifier.weight(1f).fillMaxHeight()) {
                // Top bar
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(56.dp)
                        .background(Color.White)
                        .padding(horizontal = 20.dp),
                ) {
                    Text(
                        when {
                            state.view == View.LIBRARY && state.activePlaylistId != null ->
                                state.playlists.find { it.id == state.activePlaylistId }?.name ?: "Playlist"
                            state.view == View.LIBRARY -> "Library"
                            state.view == View.NOW_PLAYING -> "Now Playing"
                            state.view == View.STATS -> "Statistics"
                            else -> "Settings"
                        },
                        fontSize = 18.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = Fp.TextPrimary,
                    )
                    if (state.view == View.LIBRARY && screenWidthDp >= 480) {
                        Spacer(Modifier.width(10.dp))
                        Text(
                            "${state.displayedTracks.size} tracks",
                            fontSize = 11.sp,
                            color = Fp.Blue,
                            fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace,
                            modifier = Modifier
                                .clip(RoundedCornerShape(8.dp))
                                .background(Fp.BlueLight)
                                .padding(horizontal = 8.dp, vertical = 2.dp),
                        )
                    }
                    Spacer(Modifier.weight(1f))
                    if (state.view == View.LIBRARY) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier
                                .weight(1f)
                                .clip(RoundedCornerShape(4.dp))
                                .background(Fp.ContentBg)
                                .padding(horizontal = 10.dp, vertical = 7.dp),
                        ) {
                            Icon(Icons.Filled.Search, contentDescription = null, tint = Fp.TextTertiary, modifier = Modifier.size(15.dp))
                            Spacer(Modifier.width(6.dp))
                            Box(Modifier.fillMaxWidth()) {
                                if (state.searchQuery.isEmpty()) {
                                    Text(
                                        "Search your library...",
                                        fontSize = 13.sp,
                                        color = Fp.TextTertiary,
                                        maxLines = 1,
                                        overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                                    )
                                }
                                androidx.compose.foundation.text.BasicTextField(
                                    value = state.searchQuery,
                                    onValueChange = { vm.onSearchQueryChange(it) },
                                    singleLine = true,
                                    textStyle = androidx.compose.ui.text.TextStyle(fontSize = 13.sp, color = Fp.TextPrimary),
                                    cursorBrush = androidx.compose.ui.graphics.SolidColor(Fp.Blue),
                                    modifier = Modifier.fillMaxWidth(),
                                )
                            }
                            if (state.searchQuery.isNotEmpty()) {
                                Spacer(Modifier.width(4.dp))
                                Text(
                                    "×",
                                    fontSize = 14.sp,
                                    color = Fp.TextTertiary,
                                    modifier = Modifier
                                        .clickable { vm.onSearchQueryChange("") }
                                        .padding(2.dp),
                                )
                            }
                        }
                        Spacer(Modifier.width(10.dp))
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier
                                .clip(RoundedCornerShape(4.dp))
                                .background(Fp.Orange)
                                .clickable { vm.openImportModal() }
                                .padding(horizontal = if (screenWidthDp < 480) 10.dp else 12.dp, vertical = 7.dp),
                        ) {
                            Icon(Icons.Filled.Add, contentDescription = null, tint = Color.White, modifier = Modifier.size(15.dp))
                            if (screenWidthDp >= 480) {
                                Spacer(Modifier.width(4.dp))
                                Text("Import", fontSize = 12.sp, color = Color.White, fontWeight = FontWeight.Medium)
                            }
                        }
                    }
                }

                // Content
                Box(Modifier.weight(1f).fillMaxWidth()) {
                    if (state.isLoading) {
                        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                            com.zprolab.FreePlayer.ui.components.LoadingSpinner()
                        }
                    } else if (!state.isSetup && state.view == View.LIBRARY) {
                        EmptyWelcome(vm)
                    } else {
                        when (state.view) {
                            View.LIBRARY -> LibraryScreen(
                                tracks = state.displayedTracks,
                                onPlay = { t, list -> PlayerController.playTrackFromList(t, list) },
                                currentTrack = state.currentTrack,
                                isPlaying = state.isPlaying,
                                sortBy = state.sortBy,
                                sortDir = state.sortDir,
                                onSort = { vm.onSort(it) },
                                activePlaylistId = state.activePlaylistId,
                                playlists = state.playlists,
                                onAddToPlaylist = { pid, tid -> vm.addToPlaylist(pid, tid) },
                                onRemoveFromPlaylist = { vm.removeFromPlaylist(it) },
                                onCreatePlaylistForTrack = { track ->
                                    vm.pendingAddTrack = track
                                    playlistModalMode = "create"
                                    playlistModalPlaylist = null
                                },
                                onEditTrack = { editingTrack = it },
                                onUploadLrc = { track ->
                                    vm.pendingLrcTrack = track
                                    lrcPicker.launch("*/*")
                                },
                                onRemoveLrc = {
                                    vm.removeLrc(it.id)
                                    if (state.currentTrack?.id == it.id) lyrics = emptyList()
                                },
                                onDeleteTrack = { vm.deleteTrack(it) },
                            )
                            View.NOW_PLAYING -> NowPlayingScreen(
                                currentTrack = state.currentTrack,
                                isPlaying = state.isPlaying,
                                currentTime = state.currentTime,
                                duration = state.duration,
                                queue = state.queue,
                                queueIndex = state.queueIndex,
                                visualizerEngine = visualizerEngine,
                                visualizerMode = state.visualizerMode,
                                onVisualizerModeChange = { vm.setVisualizerMode(it) },
                                onSeek = { PlayerController.seek(it) },
                                onTogglePlay = { PlayerController.togglePlayPause() },
                                onNext = { PlayerController.next() },
                                onPrev = { PlayerController.prev() },
                                onPlayFromQueue = { t, list -> PlayerController.playTrackFromList(t, list) },
                                lyrics = lyrics,
                                onUploadLrc = { lrcPicker.launch("*/*") },
                                onRemoveLrc = {
                                    state.currentTrack?.let { t ->
                                        vm.removeLrc(t.id)
                                        lyrics = emptyList()
                                    }
                                },
                                isImmersive = state.isImmersive,
                                onImmersiveChange = { v -> PlayerController.updateState { it.copy(isImmersive = v) } },
                            )
                            View.STATS -> StatsScreen(
                                loadStats = { cb -> vm.getStats(cb) },
                                loadHistory = { limit, cb -> vm.getPlayHistory(limit, cb) },
                            )
                            View.SETTINGS -> SettingsScreen(
                                importMode = state.importMode,
                                onImportModeChange = { vm.onImportModeChange(it) },
                                libraryDir = state.libraryDir,
                                defaultVolume = state.defaultVolume,
                                onDefaultVolumeChange = { vm.onDefaultVolumeChange(it) },
                                defaultVisualizer = state.defaultVisualizer,
                                onDefaultVisualizerChange = { vm.onDefaultVisualizerChange(it) },
                                onResetDatabase = { vm.onResetDatabase() },
                            )
                        }
                    }
                }

                // PlayerBar at the bottom of the content column (right of the sidebar)
                PlayerBar(
                    currentTrack = state.currentTrack,
                    isPlaying = state.isPlaying,
                    currentTime = state.currentTime,
                    duration = state.duration,
                    volume = state.volume,
                    playMode = state.playMode,
                    onTogglePlay = { PlayerController.togglePlayPause() },
                    onNext = { PlayerController.next() },
                    onPrev = { PlayerController.prev() },
                    onSeek = { PlayerController.seek(it) },
                    onVolumeChange = { PlayerController.setVolume(it) },
                    onPlayModeChange = { PlayerController.setPlayMode(it) },
                )
            }
        }

        // Modals
        if (state.importModalOpen) {
            ImportModal(
                importMode = state.importMode,
                libraryDir = state.libraryDir,
                onClose = { vm.closeImportModal() },
                onComplete = { vm.onImportComplete() },
            )
        }

        playlistModalMode?.let { mode ->
            PlaylistModal(
                mode = mode,
                playlist = playlistModalPlaylist,
                allTracks = state.tracks,
                onClose = { playlistModalMode = null },
                onCreate = { name, desc, ids -> vm.createPlaylist(name, desc, ids) },
                onRename = { id, name -> vm.renamePlaylist(id, name) },
                onUpdateTracks = { id, ids -> vm.updatePlaylistTracks(id, ids) },
                loadExistingTrackIds = { id -> vm.loadPlaylistTrackIds(id) },
            )
        }

        editingTrack?.let { track ->
            EditModal(
                track = track,
                onClose = { editingTrack = null },
                onSave = { id, fields -> vm.updateTrackMetadata(id, fields) },
            )
        }
    }
}

@Composable
private fun EmptyWelcome(vm: PlayerViewModel) {
    Column(
        Modifier.fillMaxSize(),
        verticalArrangement = androidx.compose.foundation.layout.Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(
            Icons.Filled.MusicNote,
            contentDescription = null,
            tint = Color(0xFFd0d0d4),
            modifier = Modifier.size(64.dp),
        )
        Spacer(Modifier.height(14.dp))
        Text(
            "Welcome to FreePlayer",
            fontSize = 20.sp,
            fontWeight = FontWeight.SemiBold,
            color = Fp.TextPrimary,
            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp),
        )
        Spacer(Modifier.height(8.dp))
        Text(
            "Set up your music library to get started. Choose a directory where your music will be stored, then import your audio files.",
            fontSize = 13.sp,
            color = Fp.TextSecondary,
            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp),
        )
        Spacer(Modifier.height(18.dp))
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .clip(RoundedCornerShape(4.dp))
                .background(Fp.Orange)
                .clickable { vm.openImportModal() }
                .padding(horizontal = 18.dp, vertical = 10.dp),
        ) {
            Icon(Icons.Filled.Add, contentDescription = null, tint = Color.White, modifier = Modifier.size(16.dp))
            Spacer(Modifier.width(6.dp))
            Text("Set Up Library", fontSize = 13.sp, color = Color.White, fontWeight = FontWeight.Medium)
        }
    }
}
