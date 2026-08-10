package com.zprolab.FreePlayer.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.zprolab.FreePlayer.audio.VisualizerEngine
import com.zprolab.FreePlayer.data.Track
import com.zprolab.FreePlayer.ui.theme.Fp
import com.zprolab.FreePlayer.util.Formatting
import com.zprolab.FreePlayer.util.LrcLine

/**
 * Port of NowPlaying.jsx — Overview / Lyrics / Scope tabs, specs table,
 * collapsible queue, and the immersive-mode overlay entry point.
 */
@Composable
fun NowPlayingScreen(
    currentTrack: Track?,
    isPlaying: Boolean,
    currentTime: Double,
    duration: Double,
    queue: List<Track>,
    queueIndex: Int,
    visualizerEngine: VisualizerEngine,
    visualizerMode: String,
    onVisualizerModeChange: (String) -> Unit,
    onSeek: (Double) -> Unit,
    onTogglePlay: () -> Unit,
    onNext: () -> Unit,
    onPrev: () -> Unit,
    onPlayFromQueue: (Track, List<Track>) -> Unit,
    lyrics: List<LrcLine>,
    onUploadLrc: () -> Unit,
    onRemoveLrc: () -> Unit,
    onFetchLyrics: () -> Unit,
    onFetchCover: () -> Unit,
    lyricsFetchState: com.zprolab.FreePlayer.data.FetchState,
    coverFetchState: com.zprolab.FreePlayer.data.FetchState,
    isImmersive: Boolean,
    onImmersiveChange: (Boolean) -> Unit,
) {
    var tab by remember { mutableIntStateOf(0) }
    val compact = LocalConfiguration.current.screenWidthDp < 600

    if (currentTrack == null) {
        Column(
            Modifier.fillMaxSize(),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Box(
                Modifier
                    .size(72.dp)
                    .clip(CircleShape)
                    .background(Fp.BorderLight),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.PlayArrow, contentDescription = null, tint = Fp.TextTertiary, modifier = Modifier.size(36.dp))
            }
            Spacer(Modifier.height(12.dp))
            Text("Nothing playing", color = Fp.TextSecondary, fontSize = 14.sp)
            Text("Select a track from your library to start listening.", color = Fp.TextTertiary, fontSize = 12.sp)
        }
        return
    }

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = if (compact) 16.dp else 28.dp, vertical = 20.dp),
    ) {
        // Tabs
        Row(
            Modifier
                .clip(RoundedCornerShape(6.dp))
                .background(Color.White)
                .padding(2.dp),
        ) {
            TabButton("Overview", tab == 0) { tab = 0 }
            TabButton("Lyrics", tab == 1) { tab = 1 }
            TabButton("Scope", tab == 2) { tab = 2 }
        }
        Spacer(Modifier.height(20.dp))

        when (tab) {
            0 -> OverviewTab(
                track = currentTrack,
                isPlaying = isPlaying,
                currentTime = currentTime,
                duration = duration,
                queue = queue,
                queueIndex = queueIndex,
                lyrics = lyrics,
                onPlayFromQueue = onPlayFromQueue,
                onSeek = onSeek,
                onTogglePlay = onTogglePlay,
                onNext = onNext,
                onPrev = onPrev,
                onUploadLrc = onUploadLrc,
                onRemoveLrc = onRemoveLrc,
                onFetchCover = onFetchCover,
                coverFetchState = coverFetchState,
                onFullscreen = { onImmersiveChange(true) },
                compact = compact,
            )
            1 -> LyricsTab(
                lyrics = lyrics,
                currentTime = currentTime,
                onUploadLrc = onUploadLrc,
                onRemoveLrc = onRemoveLrc,
                onFetchLyrics = onFetchLyrics,
                fetchState = lyricsFetchState,
                onFullscreen = { onImmersiveChange(true) },
            )
            2 -> ScopeTab(
                track = currentTrack,
                isPlaying = isPlaying,
                engine = visualizerEngine,
                mode = visualizerMode,
                onModeChange = onVisualizerModeChange,
            )
        }
    }

    if (isImmersive) {
        ImmersiveMode(
            track = currentTrack,
            isPlaying = isPlaying,
            currentTime = currentTime,
            duration = duration,
            lyrics = lyrics,
            onSeek = onSeek,
            onTogglePlay = onTogglePlay,
            onNext = onNext,
            onPrev = onPrev,
            onExit = { onImmersiveChange(false) },
        )
    }
}

@Composable
private fun TabButton(label: String, active: Boolean, onClick: () -> Unit) {
    Box(
        Modifier
            .clip(RoundedCornerShape(5.dp))
            .background(if (active) Fp.Orange else Color.White)
            .clickable(onClick = onClick)
            .padding(horizontal = 18.dp, vertical = 7.dp),
    ) {
        Text(label, color = if (active) Color.White else Fp.TextPrimary, fontSize = 13.sp)
    }
}

@Composable
private fun OverviewTab(
    track: Track,
    isPlaying: Boolean,
    currentTime: Double,
    duration: Double,
    queue: List<Track>,
    queueIndex: Int,
    lyrics: List<LrcLine>,
    onPlayFromQueue: (Track, List<Track>) -> Unit,
    onSeek: (Double) -> Unit,
    onTogglePlay: () -> Unit,
    onNext: () -> Unit,
    onPrev: () -> Unit,
    onUploadLrc: () -> Unit,
    onRemoveLrc: () -> Unit,
    onFetchCover: () -> Unit,
    coverFetchState: com.zprolab.FreePlayer.data.FetchState,
    onFullscreen: () -> Unit,
    compact: Boolean,
) {
    if (compact) {
        Column(Modifier.fillMaxWidth()) {
            TrackDetails(
                track,
                coverSize = 160.dp,
                titleSize = 22,
                onFetchCover = onFetchCover,
                coverFetchState = coverFetchState,
            )
            Spacer(Modifier.height(20.dp))
            LyricsDisplay(
                lines = lyrics,
                currentTime = currentTime,
                autoScroll = true,
                onFullscreen = onFullscreen,
                onUpload = onUploadLrc,
                onRemoveLrc = onRemoveLrc,
                modifier = Modifier.fillMaxWidth().height(260.dp),
            )
            if (queue.size > 1) {
                QueuePanel(queue, queueIndex, isPlaying, onPlayFromQueue, compact = true)
            }
        }
    } else {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(32.dp)) {
            TrackDetails(
                track,
                coverSize = 200.dp,
                titleSize = 26,
                onFetchCover = onFetchCover,
                coverFetchState = coverFetchState,
                modifier = Modifier.width(280.dp),
            )
            Column(Modifier.weight(1f)) {
                LyricsDisplay(
                    lines = lyrics,
                    currentTime = currentTime,
                    autoScroll = true,
                    onFullscreen = onFullscreen,
                    onUpload = onUploadLrc,
                    onRemoveLrc = onRemoveLrc,
                    modifier = Modifier.fillMaxWidth().height(420.dp),
                )
                if (queue.size > 1) {
                    QueuePanel(queue, queueIndex, isPlaying, onPlayFromQueue, compact = false)
                }
            }
        }
    }
}

@Composable
private fun TrackDetails(
    track: Track,
    coverSize: androidx.compose.ui.unit.Dp,
    titleSize: Int,
    onFetchCover: () -> Unit,
    coverFetchState: com.zprolab.FreePlayer.data.FetchState,
    modifier: Modifier = Modifier,
) {
    Column(modifier) {
        CoverArt(track.coverPath, size = coverSize, cornerRadius = 8.dp)
        if (track.coverPath.isNullOrBlank() || coverFetchState != com.zprolab.FreePlayer.data.FetchState.IDLE) {
            Spacer(Modifier.height(8.dp))
            Box(
                Modifier
                    .clip(RoundedCornerShape(5.dp))
                    .background(Fp.ContentBg)
                    .clickable(
                        enabled = coverFetchState != com.zprolab.FreePlayer.data.FetchState.FETCHING,
                        onClick = onFetchCover,
                    )
                    .padding(horizontal = 10.dp, vertical = 6.dp),
            ) {
                Text(
                    when (coverFetchState) {
                        com.zprolab.FreePlayer.data.FetchState.FETCHING -> "Finding cover…"
                        com.zprolab.FreePlayer.data.FetchState.NOT_FOUND -> "Cover not found · Retry"
                        com.zprolab.FreePlayer.data.FetchState.FAILED -> "Cover lookup failed · Retry"
                        com.zprolab.FreePlayer.data.FetchState.IDLE -> "Find cover online"
                    },
                    fontSize = 11.sp,
                    color = if (coverFetchState == com.zprolab.FreePlayer.data.FetchState.FAILED) Fp.Orange else Fp.TextSecondary,
                )
            }
        }
        Spacer(Modifier.height(16.dp))
        Text(
            track.title,
            fontSize = titleSize.sp,
            fontWeight = FontWeight(650),
            color = Fp.TextPrimary,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
        Text(track.artist, fontSize = 15.sp, fontWeight = FontWeight.Medium, color = Fp.TextPrimary)
        if (track.album != "Unknown Album") {
            Text(track.album, fontSize = 13.sp, color = Fp.TextSecondary)
        }
        Spacer(Modifier.height(12.dp))
        SpecRow("Format", track.fileFormat?.uppercase())
        SpecRow("Bitrate", Formatting.formatBitrate(track.bitrate))
        SpecRow("Sample", Formatting.formatSampleRate(track.sampleRate))
        SpecRow("Year", track.year?.toString())
        SpecRow("Genre", track.genre)
    }
}

@Composable
private fun SpecRow(label: String, value: String?) {
    if (value == null) return
    Row(
        Modifier
            .fillMaxWidth()
            .padding(vertical = 7.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            label.uppercase(),
            fontSize = 10.sp,
            color = Fp.TextTertiary,
            fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace,
            modifier = Modifier.width(60.dp),
        )
        Text(value, fontSize = 12.sp, color = Fp.TextPrimary)
    }
    Box(Modifier.fillMaxWidth().height(1.dp).background(Fp.BorderLight))
}

@Composable
private fun LyricsTab(
    lyrics: List<LrcLine>,
    currentTime: Double,
    onUploadLrc: () -> Unit,
    onRemoveLrc: () -> Unit,
    onFetchLyrics: () -> Unit,
    fetchState: com.zprolab.FreePlayer.data.FetchState,
    onFullscreen: () -> Unit,
) {
    LyricsDisplay(
        lines = lyrics,
        currentTime = currentTime,
        autoScroll = true,
        onFullscreen = onFullscreen,
        onUpload = onUploadLrc,
        onRemoveLrc = onRemoveLrc,
        onFetchLyrics = onFetchLyrics,
        fetchState = fetchState,
        modifier = Modifier.fillMaxWidth().height(640.dp),
    )
}

@Composable
private fun ScopeTab(
    track: Track,
    isPlaying: Boolean,
    engine: VisualizerEngine,
    mode: String,
    onModeChange: (String) -> Unit,
) {
    Column {
        Text(
            "MONITORING · ${track.title} — ${track.artist} ${track.fileFormat?.uppercase() ?: ""}",
            fontSize = 11.sp,
            color = Color(0x99303030),
            fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace,
        )
        Spacer(Modifier.height(8.dp))
        WaveformVisualizer(
            engine = engine,
            isPlaying = isPlaying,
            trackId = track.id,
            mode = mode,
            onModeChange = onModeChange,
        )
    }
}

@Composable
private fun QueuePanel(
    queue: List<Track>,
    queueIndex: Int,
    isPlaying: Boolean,
    onPlayFromQueue: (Track, List<Track>) -> Unit,
    compact: Boolean,
) {
    var expanded by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxWidth().padding(top = 8.dp)) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth().clickable { expanded = !expanded },
        ) {
            Text("Queue", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = Fp.TextPrimary)
            Spacer(Modifier.width(8.dp))
            Text(
                queue.size.toString(),
                fontSize = 10.sp,
                color = Fp.Blue,
                fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace,
                modifier = Modifier
                    .clip(RoundedCornerShape(8.dp))
                    .background(Fp.BlueLight)
                    .padding(horizontal = 6.dp, vertical = 1.dp),
            )
            Spacer(Modifier.weight(1f))
            Icon(
                if (expanded) Icons.Filled.KeyboardArrowDown else Icons.Filled.KeyboardArrowRight,
                contentDescription = null,
                tint = Fp.TextTertiary,
                modifier = Modifier.size(18.dp),
            )
        }
        if (expanded) {
            Column(Modifier.fillMaxWidth()) {
                queue.forEachIndexed { i, t ->
                    val current = i == queueIndex
                    val played = i < queueIndex
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(if (current) Fp.OrangeLight else Color.Transparent)
                            .clickable { onPlayFromQueue(t, queue) }
                            .padding(vertical = 6.dp),
                    ) {
                        if (current && isPlaying) {
                            EqualizerBars(active = true, modifier = Modifier.width(16.dp))
                        } else {
                            Text(
                                (i + 1).toString(),
                                fontSize = 11.sp,
                                color = if (current) Fp.Orange else Fp.TextTertiary,
                                fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace,
                                modifier = Modifier.width(16.dp),
                            )
                        }
                        Spacer(Modifier.width(8.dp))
                        Text(
                            t.title,
                            fontSize = 13.sp,
                            fontWeight = if (current) FontWeight.Bold else FontWeight.Normal,
                            color = if (current) Fp.Orange else Fp.TextPrimary.copy(alpha = if (played) 0.35f else 1f),
                            maxLines = 1,
                            modifier = Modifier.weight(1f),
                        )
                        Spacer(Modifier.width(8.dp))
                        Text(
                            t.artist,
                            fontSize = 11.sp,
                            color = Fp.TextSecondary,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = if (compact) Modifier.width(72.dp) else Modifier.width(160.dp),
                        )
                        Text(
                            Formatting.formatTrackDuration(t.duration),
                            fontSize = 11.sp,
                            color = Fp.TextTertiary,
                            fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace,
                        )
                    }
                }
            }
        }
    }
}
