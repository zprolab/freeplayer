package com.zprolab.FreePlayer.ui.components

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.zprolab.FreePlayer.data.Track
import com.zprolab.FreePlayer.ui.theme.Fp
import com.zprolab.FreePlayer.util.Formatting
import com.zprolab.FreePlayer.util.LrcLine
import com.zprolab.FreePlayer.util.LrcParser
import kotlinx.coroutines.delay

private val ZOOM_STEPS = listOf(-2, -1, 0, 1, 2, 3, 4)

/**
 * Port of ImmersiveMode.jsx — fullscreen overlay with rotating cover,
 * zoom controls, karaoke-style lyrics, seek + transport.
 * Esc / close button exits.
 */
@Composable
fun ImmersiveMode(
    track: Track,
    isPlaying: Boolean,
    currentTime: Double,
    duration: Double,
    lyrics: List<LrcLine>,
    onSeek: (Double) -> Unit,
    onTogglePlay: () -> Unit,
    onNext: () -> Unit,
    onPrev: () -> Unit,
    onExit: () -> Unit,
) {
    var zoom by remember { mutableIntStateOf(0) }
    val listState = rememberLazyListState()
    val activeIndex = LrcParser.activeIndex(lyrics, currentTime)
    var prevActive by remember { mutableIntStateOf(-1) }

    LaunchedEffect(activeIndex) {
        if (activeIndex >= 0 && activeIndex != prevActive) {
            delay(80)
            listState.animateScrollToItem((activeIndex - 2).coerceAtLeast(0))
        }
        prevActive = activeIndex
    }

    val transition = rememberInfiniteTransition(label = "cover-spin")
    val rotation by transition.animateFloat(
        initialValue = 0f,
        targetValue = 360f,
        animationSpec = infiniteRepeatable(tween(20000, easing = LinearEasing)),
        label = "spin",
    )

    val bg = Brush.radialGradient(
        colors = listOf(
            Fp.Orange.copy(alpha = 0.28f),
            Fp.Orange.copy(alpha = 0.16f),
            Fp.Orange.copy(alpha = 0.10f),
            Fp.ImmersiveBg,
        ),
        center = androidx.compose.ui.geometry.Offset(0.25f, 0.2f),
    )

    Box(
        Modifier
            .fillMaxSize()
            .background(bg)
            .pointerInput(Unit) {
                detectTapGestures { }
            },
    ) {
        Column(Modifier.fillMaxSize()) {
            // Top bar
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(24.dp, 24.dp, 28.dp, 0.dp),
            ) {
                CoverArt(track.coverPath, size = 64.dp, cornerRadius = 6.dp, modifier = if (isPlaying) Modifier.rotate(rotation) else Modifier)
                Spacer(Modifier.width(14.dp))
                Column {
                    Text(track.title, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = Color.White.copy(alpha = 0.9f), maxLines = 1)
                    Text(track.artist, fontSize = 13.sp, color = Color.White.copy(alpha = 0.45f), maxLines = 1)
                }
                Spacer(Modifier.weight(1f))
                // zoom controls
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier
                        .clip(RoundedCornerShape(6.dp))
                        .background(Color.White.copy(alpha = 0.08f))
                        .padding(horizontal = 6.dp, vertical = 4.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    ZoomButton(Icons.Filled.Remove) {
                        if (zoom > ZOOM_STEPS.first()) zoom--
                    }
                    Text(
                        "${22 + zoom * 4}px",
                        color = Color.White.copy(alpha = 0.6f),
                        fontSize = 11.sp,
                        fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace,
                    )
                    ZoomButton(Icons.Filled.Add) {
                        if (zoom < ZOOM_STEPS.last()) zoom++
                    }
                }
                Spacer(Modifier.width(12.dp))
                Box(
                    Modifier
                        .size(36.dp)
                        .clip(CircleShape)
                        .clickable(onClick = onExit),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.Filled.Close, contentDescription = "Exit immersive mode (Esc)", tint = Color.White.copy(alpha = 0.7f), modifier = Modifier.size(20.dp))
                }
            }

            // Lyrics center
            Box(Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) {
                if (lyrics.isEmpty()) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        CoverArt(track.coverPath, size = 160.dp, cornerRadius = 10.dp)
                        Spacer(Modifier.height(18.dp))
                        Text(track.title, fontSize = 22.sp, color = Color.White.copy(alpha = 0.9f))
                        Text(track.artist, fontSize = 14.sp, color = Color.White.copy(alpha = 0.45f))
                        Spacer(Modifier.height(12.dp))
                        Text("No synced lyrics", fontSize = 13.sp, color = Color.White.copy(alpha = 0.3f))
                    }
                } else {
                    LazyColumn(state = listState, modifier = Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
                        items(lyrics.size) { i ->
                            val line = lyrics[i]
                            val active = i == activeIndex
                            val fontSize = if (active) (22 + zoom * 4).sp else ((22 + zoom * 4 - 6).coerceAtLeast(12)).sp
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                modifier = Modifier.fillMaxWidth().padding(horizontal = 48.dp, vertical = 14.dp),
                            ) {
                                if (active) {
                                    Box(Modifier.width(3.dp).height(28.dp).background(Fp.Orange, RoundedCornerShape(2.dp)))
                                } else {
                                    Spacer(Modifier.width(3.dp))
                                }
                                Text(
                                    formatImmersiveTime(line.time),
                                    fontSize = 10.sp,
                                    color = Color.White.copy(alpha = if (active) 0.7f else 0.0f),
                                    fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace,
                                    textAlign = TextAlign.End,
                                    modifier = Modifier.width(46.dp),
                                )
                                Spacer(Modifier.width(14.dp))
                                Text(
                                    line.text,
                                    fontSize = fontSize,
                                    fontWeight = if (active) FontWeight.SemiBold else FontWeight.Normal,
                                    color = if (active) Fp.Orange else Color.White.copy(alpha = if (i < activeIndex) 0.35f else 0.5f),
                                    modifier = Modifier.weight(1f),
                                )
                            }
                        }
                    }
                }
            }

            // Bottom bar
            Column(Modifier.fillMaxWidth().padding(horizontal = 48.dp, vertical = 32.dp)) {
                // progress bar (tap to seek)
                val progress = if (duration > 0) (currentTime / duration).toFloat().coerceIn(0f, 1f) else 0f
                Box(
                    Modifier
                        .fillMaxWidth()
                        .height(4.dp)
                        .clip(RoundedCornerShape(2.dp))
                        .background(Color.White.copy(alpha = 0.1f))
                        .pointerInput(duration) {
                            detectTapGestures { offset ->
                                if (duration > 0) onSeek((offset.x / size.width) * duration)
                            }
                        },
                ) {
                    Box(
                        Modifier
                            .fillMaxWidth(progress)
                            .fillMaxHeight()
                            .background(
                                Brush.horizontalGradient(listOf(Fp.Orange.copy(alpha = 0.8f), Fp.Orange)),
                                RoundedCornerShape(2.dp),
                            )
                    )
                }
                Spacer(Modifier.height(6.dp))
                Row(Modifier.fillMaxWidth()) {
                    Text(Formatting.formatTime(currentTime), fontSize = 11.sp, color = Color.White.copy(alpha = 0.25f), fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace)
                    Spacer(Modifier.weight(1f))
                    Text(Formatting.formatTime(duration), fontSize = 11.sp, color = Color.White.copy(alpha = 0.25f), fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace)
                }
                Spacer(Modifier.height(12.dp))
                Row(
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    RoundControl(52.dp, 22.dp, Icons.Filled.SkipPrevious, onPrev)
                    Spacer(Modifier.width(32.dp))
                    Box(
                        Modifier
                            .size(72.dp)
                            .clip(CircleShape)
                            .background(Color.White.copy(alpha = 0.1f))
                            .clickable(onClick = onTogglePlay),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            if (isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                            contentDescription = null,
                            tint = Color.White,
                            modifier = Modifier.size(40.dp),
                        )
                    }
                    Spacer(Modifier.width(32.dp))
                    RoundControl(52.dp, 22.dp, Icons.Filled.SkipNext, onNext)
                }
            }
        }
    }
}

@Composable
private fun ZoomButton(icon: androidx.compose.ui.graphics.vector.ImageVector, onClick: () -> Unit) {
    Box(
        Modifier
            .size(24.dp)
            .clip(RoundedCornerShape(4.dp))
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = null, tint = Color.White.copy(alpha = 0.7f), modifier = Modifier.size(16.dp))
    }
}

@Composable
private fun RoundControl(size: androidx.compose.ui.unit.Dp, iconSize: androidx.compose.ui.unit.Dp, icon: androidx.compose.ui.graphics.vector.ImageVector, onClick: () -> Unit) {
    Box(
        Modifier
            .size(size)
            .clip(CircleShape)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = null, tint = Color.White.copy(alpha = 0.8f), modifier = Modifier.size(iconSize))
    }
}

private fun formatImmersiveTime(time: Double): String {
    val m = (time / 60).toInt()
    val s = (time % 60).toInt()
    return "$m:${s.toString().padStart(2, '0')}"
}
