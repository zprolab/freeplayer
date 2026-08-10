package com.zprolab.FreePlayer.playback

import android.content.Context
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import com.zprolab.FreePlayer.data.Database
import com.zprolab.FreePlayer.data.Track
import com.zprolab.FreePlayer.util.Formatting
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import java.io.File
import kotlin.math.pow
import kotlin.math.roundToLong

enum class View { LIBRARY, NOW_PLAYING, STATS, SETTINGS }

data class PlayerUiState(
    val view: View = View.LIBRARY,
    val tracks: List<Track> = emptyList(),
    val currentTrack: Track? = null,
    val isPlaying: Boolean = false,
    val queue: List<Track> = emptyList(),
    val queueIndex: Int = -1,
    val shuffledQueue: List<Long> = emptyList(),
    val currentTime: Double = 0.0,
    val duration: Double = 0.0,
    val volume: Float = 0.8f,
    val isLoading: Boolean = true,
    val isSetup: Boolean = false,
    val libraryDir: String = "",
    val searchQuery: String = "",
    val sortBy: String = "imported_at",
    val sortDir: String = "DESC",
    val visualizerMode: String = "waveform",
    val importMode: String = "copy",
    val importModalOpen: Boolean = false,
    val defaultVolume: Float = 0.8f,
    val defaultVisualizer: String = "waveform",
    val playMode: String = QueueLogic.MODE_SEQUENTIAL,
    val playlists: List<com.zprolab.FreePlayer.data.Playlist> = emptyList(),
    val activePlaylistId: Long? = null,
    val playlistTracks: List<Track> = emptyList(),
    val dragOver: Boolean = false,
    val isImmersive: Boolean = false,
    val lyricsFetchState: com.zprolab.FreePlayer.data.FetchState = com.zprolab.FreePlayer.data.FetchState.IDLE,
    val coverFetchState: com.zprolab.FreePlayer.data.FetchState = com.zprolab.FreePlayer.data.FetchState.IDLE,
    val backfillDone: Int = 0,
    val backfillTotal: Int = 0,
) {
    val displayedTracks: List<Track>
        get() = if (activePlaylistId == null) tracks else playlistTracks

    fun backfillProgress(): Pair<Int, Int>? = if (backfillTotal > 0) backfillDone to backfillTotal else null
}

/**
 * Singleton playback controller — the Android counterpart of
 * usePlayer + usePlayback + audioEngine. ExoPlayer is created lazily
 * (first play) so UI can render before playback starts.
 */
object PlayerController {

    lateinit var appContext: Context
        private set
    lateinit var db: Database
        private set

    private var player: ExoPlayer? = null

    private val _state = MutableStateFlow(PlayerUiState())
    val state: StateFlow<PlayerUiState> = _state

    private var playSessionId: Long? = null
    private var playSessionStartMs: Long = 0

    private val listener = object : Player.Listener {
        override fun onIsPlayingChanged(isPlaying: Boolean) {
            _state.update { it.copy(isPlaying = isPlaying) }
        }

        override fun onPlaybackStateChanged(playbackState: Int) {
            when (playbackState) {
                Player.STATE_READY -> {
                    // Audio session becomes valid once prepared — bind the EQ.
                    player?.let { com.zprolab.FreePlayer.audio.EqualizerEngine.attach(it.audioSessionId) }
                }
                Player.STATE_ENDED -> {
                    if (_state.value.playMode == QueueLogic.MODE_REPEAT_ONE) {
                        player?.seekTo(0)
                        player?.play()
                    } else {
                        next()
                    }
                }
            }
        }

        override fun onPlayerError(error: PlaybackException) {
            // 1:1 with desktop onError logging; playback stops
        }
    }

    fun init(context: Context) {
        appContext = context.applicationContext
        db = Database.get(appContext)
        com.zprolab.FreePlayer.audio.EqualizerEngine.restore()
    }

    private fun ensurePlayer(): ExoPlayer {
        val existing = player
        if (existing != null) return existing
        val p = ExoPlayer.Builder(appContext).build()
        p.setAudioAttributes(
            androidx.media3.common.AudioAttributes.Builder()
                .setUsage(androidx.media3.common.C.USAGE_MEDIA)
                .setContentType(androidx.media3.common.C.AUDIO_CONTENT_TYPE_MUSIC)
                .build(),
            true, // handleAudioFocus: pause/duck on other apps (platform-only addition)
        )
        p.addListener(listener)
        player = p
        p.volume = (_state.value.volume * replayGainMultiplier(_state.value.currentTrack)).coerceIn(0f, 1f)
        // Attach the equalizer to the audio session (no-op until prepared).
        com.zprolab.FreePlayer.audio.EqualizerEngine.attach(p.audioSessionId)
        return p
    }

    fun getPlayer(): ExoPlayer? = player

    fun getOrCreatePlayer(): ExoPlayer = ensurePlayer()

    private fun replayGainMultiplier(track: Track?): Float {
        val gainDb = track?.replaygainGain ?: 0.0
        return (10.0.pow(gainDb / 20.0)).toFloat().coerceIn(0f, 4f)
    }

    private fun applyVolume() {
        val p = player ?: return
        val base = _state.value.volume
        p.volume = (base * replayGainMultiplier(_state.value.currentTrack)).coerceIn(0f, 1f)
    }

    // ── play session (1:1 playStart/playEnd lifecycle) ──

    private fun endPlaySession() {
        val sid = playSessionId ?: return
        val elapsed = (System.currentTimeMillis() - playSessionStartMs) / 1000.0
        val trackDuration = _state.value.duration
        val percentage = if (trackDuration > 0) {
            ((elapsed / trackDuration) * 100).coerceAtMost(100.0)
        } else 0.0
        db.endPlaySession(sid, elapsed.roundToLong().toDouble(), percentage.roundToLong().toDouble())
        playSessionId = null
    }

    private fun startPlaySession(trackId: Long) {
        endPlaySession()
        playSessionId = db.startPlaySession(trackId)
        playSessionStartMs = System.currentTimeMillis()
    }

    // ── playback control (mirrors usePlayback) ──

    fun playTrack(track: Track) {
        endPlaySession()
        val p = ensurePlayer()
        _state.update { it.copy(currentTrack = track) }
        // MediaItem metadata drives the MediaSession notification
        // (counterpart of MPNowPlayingInfo on desktop).
        p.setMediaItem(
            MediaItem.Builder()
                .setUri(track.filePath)
                .setMediaMetadata(
                    androidx.media3.common.MediaMetadata.Builder()
                        .setTitle(track.title)
                        .setArtist(track.artist)
                        .setAlbumTitle(track.album.ifEmpty { null })
                        .setArtworkUri(track.coverPath?.let { android.net.Uri.fromFile(File(it)) })
                        .build()
                )
                .build()
        )
        p.prepare()
        applyVolume()
        p.play()
        startPlaySession(track.id)
        // Bring the playback service up so the notification appears
        // (Android counterpart of the tray "now playing" row).
        runCatching {
            appContext.startForegroundService(
                android.content.Intent(appContext, com.zprolab.FreePlayer.media.PlaybackService::class.java)
            )
        }
    }

    fun togglePlayPause() {
        val p = player
        val s = _state.value
        if (p == null || (s.currentTrack == null && s.queue.isEmpty())) {
            if (s.tracks.isNotEmpty()) {
                playTrackFromList(s.tracks[0], s.tracks)
            }
            return
        }
        if (p.isPlaying) p.pause() else p.play()
    }

    fun next() {
        val s = _state.value
        val queue = s.queue
        if (queue.isEmpty()) return
        if (s.playMode == QueueLogic.MODE_REPEAT_ONE) {
            player?.seekTo(0)
            player?.play()
            return
        }
        val queueIds = queue.map { it.id }
        var nextIdx: Int
        if (s.playMode == QueueLogic.MODE_SHUFFLE) {
            val shuffled = if (s.shuffledQueue.isNotEmpty()) s.shuffledQueue else queueIds
            val current = queueIds[s.queueIndex.coerceAtLeast(0)]
            val curIdx = shuffled.indexOf(current)
            if (curIdx < shuffled.size - 1) {
                nextIdx = queueIds.indexOf(shuffled[curIdx + 1])
            } else {
                val reshuffled = QueueLogic.shuffleArray(queueIds)
                _state.update { it.copy(shuffledQueue = reshuffled) }
                nextIdx = queueIds.indexOf(reshuffled[0])
            }
        } else {
            nextIdx = QueueLogic.getNextIndex(queueIds, s.queueIndex, s.playMode, s.shuffledQueue)
        }
        _state.update { it.copy(queueIndex = nextIdx) }
        playTrack(queue[nextIdx])
    }

    fun prev() {
        val s = _state.value
        val queue = s.queue
        if (queue.isEmpty()) return
        val p = player ?: return
        if (p.currentPosition > 3000) {
            p.seekTo(0)
            return
        }
        val queueIds = queue.map { it.id }
        val prevIdx = QueueLogic.getPrevIndex(queueIds, s.queueIndex, p.currentPosition / 1000.0, s.playMode, s.shuffledQueue)
        _state.update { it.copy(queueIndex = prevIdx) }
        playTrack(queue[prevIdx])
    }

    fun seek(time: Double) {
        val p = player ?: return
        p.seekTo((time * 1000).toLong())
        _state.update { it.copy(currentTime = time) }
    }

    fun seekToFraction(fraction: Float) {
        val dur = _state.value.duration
        if (dur > 0) seek(fraction * dur)
    }

    fun setVolume(vol: Float) {
        val v = vol.coerceIn(0f, 1f)
        _state.update { it.copy(volume = v) }
        applyVolume()
        db.setSetting("volume", v.toString())
    }

    fun setPlayMode(mode: String) {
        _state.update {
            it.copy(
                playMode = mode,
                shuffledQueue = if (mode == QueueLogic.MODE_SHUFFLE) it.shuffledQueue else emptyList(),
            )
        }
    }

    fun playTrackFromList(track: Track, trackList: List<Track>) {
        val s = _state.value
        _state.update { it.copy(queue = trackList, queueIndex = trackList.indexOfFirst { t -> t.id == track.id }) }
        if (s.playMode == QueueLogic.MODE_SHUFFLE) {
            val shuffled = QueueLogic.shuffleArray(trackList.map { it.id }).toMutableList()
            val clickedIdx = shuffled.indexOf(track.id)
            if (clickedIdx > 0) {
                shuffled[0] = shuffled[clickedIdx].also { shuffled[clickedIdx] = shuffled[0] }
            }
            _state.update { it.copy(shuffledQueue = shuffled) }
        }
        playTrack(track)
    }

    fun stopPlayback() {
        endPlaySession()
        player?.stop()
        player?.release()
        player = null
        _state.update { it.copy(currentTrack = null, isPlaying = false, queue = emptyList(), queueIndex = -1) }
    }

    fun updateState(transform: (PlayerUiState) -> PlayerUiState) {
        _state.update(transform)
    }

    fun setCurrentTime(time: Double) = _state.update { it.copy(currentTime = time) }
    fun setDuration(duration: Double) = _state.update { it.copy(duration = duration) }
}
