package com.zprolab.FreePlayer.ui.components

import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.background
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Repeat
import androidx.compose.material.icons.filled.RepeatOne
import androidx.compose.material.icons.filled.Shuffle
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material.icons.filled.VolumeDown
import androidx.compose.material.icons.filled.VolumeOff
import androidx.compose.material.icons.filled.Equalizer
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.zprolab.FreePlayer.data.Track
import com.zprolab.FreePlayer.playback.QueueLogic
import com.zprolab.FreePlayer.ui.theme.Fp
import com.zprolab.FreePlayer.util.Formatting

/**
 * Bottom playback bar — port of PlayerBar.jsx. Fixed at the bottom,
 * offset to the right of the 220dp sidebar.
 */
@Composable
fun PlayerBar(
    currentTrack: Track?,
    isPlaying: Boolean,
    currentTime: Double,
    duration: Double,
    volume: Float,
    playMode: String,
    onTogglePlay: () -> Unit,
    onNext: () -> Unit,
    onPrev: () -> Unit,
    onSeek: (Double) -> Unit,
    onVolumeChange: (Float) -> Unit,
    onPlayModeChange: (String) -> Unit,
    onOpenEqualizer: (() -> Unit)? = null,
) {
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        if (maxWidth < 560.dp) {
            CompactPlayerBar(
                currentTrack = currentTrack,
                isPlaying = isPlaying,
                currentTime = currentTime,
                duration = duration,
                onTogglePlay = onTogglePlay,
                onNext = onNext,
                onPrev = onPrev,
                onOpenEqualizer = onOpenEqualizer,
            )
        } else {
            Column(
            Modifier
                .fillMaxWidth()
                .height(78.dp)
                .background(Color.White)
                .padding(top = 6.dp),
        ) {
            // progress line
            val progress = if (duration > 0) (currentTime / duration).toFloat().coerceIn(0f, 1f) else 0f
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(3.dp)
                    .background(Fp.BorderLight)
                    .pointerInput(duration) {
                        detectTapGestures { offset ->
                            onSeek((offset.x / size.width.toFloat()) * duration)
                        }
                    },
            ) {
                Box(
                    Modifier
                        .fillMaxWidth(progress)
                        .fillMaxHeight()
                        .background(Fp.Orange)
                )
            }

            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(16.dp),
                modifier = Modifier
                    .fillMaxWidth()
                    .height(66.dp)
                    .padding(horizontal = 20.dp),
            ) {                // Left: cover + title/artist
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.weight(1.4f)) {
                    CoverArt(currentTrack?.coverPath, size = 40.dp, cornerRadius = 4.dp)
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text(
                            currentTrack?.title ?: "No track selected",
                            fontSize = 13.sp,
                            fontWeight = if (currentTrack != null) androidx.compose.ui.text.font.FontWeight.Medium else androidx.compose.ui.text.font.FontWeight.Normal,
                            color = if (currentTrack != null) Fp.TextPrimary else Fp.TextSecondary,
                            maxLines = 1,
                            overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                        )
                        Text(
                            currentTrack?.artist ?: "Select a track from your library",
                            fontSize = 11.sp,
                            color = Fp.TextSecondary,
                            maxLines = 1,
                            overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                        )
                    }
                }

                // Center: transport controls
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    IconButton(16.dp, Icons.Filled.SkipPrevious, "Previous") { onPrev() }
                    Box(
                        Modifier
                            .size(40.dp)
                            .clip(CircleShape)
                            .background(Fp.Dark)
                            .clickable { onTogglePlay() },
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            if (isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                            contentDescription = null,
                            tint = Color.White,
                            modifier = Modifier.size(22.dp),
                        )
                    }
                    IconButton(16.dp, Icons.Filled.SkipNext, "Next") { onNext() }
                }

                // Right: play modes + time + volume
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    ModeButton(Icons.Filled.Repeat, playMode == QueueLogic.MODE_SEQUENTIAL, "List Loop") { onPlayModeChange(QueueLogic.MODE_SEQUENTIAL) }
                    ModeButton(Icons.Filled.RepeatOne, playMode == QueueLogic.MODE_REPEAT_ONE, "Repeat One") { onPlayModeChange(QueueLogic.MODE_REPEAT_ONE) }
                    ModeButton(Icons.Filled.Shuffle, playMode == QueueLogic.MODE_SHUFFLE, "Shuffle") { onPlayModeChange(QueueLogic.MODE_SHUFFLE) }
                    Text(
                        "${Formatting.formatTime(currentTime)} / ${Formatting.formatTime(duration)}",
                        fontSize = 11.sp,
                        color = Fp.TextSecondary,
                        fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace,
                    )
                    if (onOpenEqualizer != null) {
                        ModeButton(Icons.Filled.Equalizer, false, "Equalizer") { onOpenEqualizer() }
                    }
                    VolumeControl(volume, onVolumeChange)
                }
            }
            }
        }
    }
}

@Composable
private fun CompactPlayerBar(
    currentTrack: Track?,
    isPlaying: Boolean,
    currentTime: Double,
    duration: Double,
    onTogglePlay: () -> Unit,
    onNext: () -> Unit,
    onPrev: () -> Unit,
    onOpenEqualizer: (() -> Unit)? = null,
) {
    Column(
        Modifier
            .fillMaxWidth()
            .height(86.dp)
            .background(Color.White)
            .padding(horizontal = 12.dp, vertical = 4.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            Text(
                currentTrack?.title ?: "No track selected",
                color = if (currentTrack == null) Fp.TextSecondary else Fp.TextPrimary,
                fontSize = 12.sp,
                maxLines = 1,
                overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f),
            )
            Text(
                "${Formatting.formatTime(currentTime)} / ${Formatting.formatTime(duration)}",
                color = Fp.TextSecondary,
                fontSize = 10.sp,
                fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace,
            )
        }
        Row(
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth(),
        ) {
            IconButton(16.dp, Icons.Filled.SkipPrevious, "Previous") { onPrev() }
            Box(
                Modifier
                    .size(36.dp)
                    .clip(CircleShape)
                    .background(Fp.Dark)
                    .clickable { onTogglePlay() },
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    if (isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                    contentDescription = null,
                    tint = Color.White,
                    modifier = Modifier.size(20.dp),
                )
            }
            IconButton(16.dp, Icons.Filled.SkipNext, "Next") { onNext() }
            if (onOpenEqualizer != null) {
                ModeButton(Icons.Filled.Equalizer, false, "Equalizer") { onOpenEqualizer() }
            }
        }
    }
}

@Composable
private fun IconButton(size: Dp, icon: androidx.compose.ui.graphics.vector.ImageVector, desc: String, onClick: () -> Unit) {
    Box(
        Modifier
            .size(32.dp)
            .clip(CircleShape)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = desc, tint = Fp.TextPrimary, modifier = Modifier.size(size))
    }
}

@Composable
private fun ModeButton(icon: androidx.compose.ui.graphics.vector.ImageVector, active: Boolean, title: String, onClick: () -> Unit) {
    Box(
        Modifier
            .size(28.dp, 26.dp)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = title, tint = if (active) Fp.Orange else Fp.TextTertiary, modifier = Modifier.size(14.dp))
    }
}

@Composable
private fun VolumeControl(volume: Float, onChange: (Float) -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        val icon = when {
            volume <= 0f -> Icons.Filled.VolumeOff
            volume <= 0.5f -> Icons.Filled.VolumeDown
            else -> Icons.Filled.VolumeUp
        }
        Icon(icon, contentDescription = null, tint = Fp.TextSecondary, modifier = Modifier.size(18.dp))
        Spacer(Modifier.width(4.dp))
        Box(
            Modifier
                .width(80.dp)
                .height(16.dp)
                .pointerInput(Unit) {
                    detectDragGestures { change, _ ->
                        val fraction = (change.position.x / size.width.toFloat()).coerceIn(0f, 1f)
                        onChange(fraction)
                        change.consume()
                    }
                    detectTapGestures { offset ->
                        onChange((offset.x / size.width.toFloat()).coerceIn(0f, 1f))
                    }
                },
            contentAlignment = Alignment.CenterStart,
        ) {
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(4.dp)
                    .clip(RoundedCornerShape(2.dp))
                    .background(Fp.BorderLight),
            ) {
                Box(
                    Modifier
                        .fillMaxWidth(volume)
                        .fillMaxHeight()
                        .background(Fp.TextPrimary, RoundedCornerShape(2.dp))
                )
            }
        }
    }
}
