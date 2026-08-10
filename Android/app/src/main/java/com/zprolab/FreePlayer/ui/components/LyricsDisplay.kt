package com.zprolab.FreePlayer.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Fullscreen
import androidx.compose.material.icons.filled.Lyrics
import androidx.compose.material.icons.filled.Upload
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.zprolab.FreePlayer.ui.theme.Fp
import com.zprolab.FreePlayer.util.LrcLine
import com.zprolab.FreePlayer.util.LrcParser
import kotlinx.coroutines.delay

/**
 * Port of LyricsDisplay.jsx — whole-line 3-state highlight (no per-word karaoke),
 * auto-centering scroll, encoding fallback handled upstream.
 */
@Composable
fun LyricsDisplay(
    lines: List<LrcLine>,
    currentTime: Double,
    autoScroll: Boolean,
    onFullscreen: () -> Unit,
    onUpload: () -> Unit,
    onRemoveLrc: () -> Unit,
    onFetchLyrics: (() -> Unit)? = null,
    fetchState: com.zprolab.FreePlayer.data.FetchState = com.zprolab.FreePlayer.data.FetchState.IDLE,
    modifier: Modifier = Modifier,
) {
    val listState = rememberLazyListState()
    val activeIndex = LrcParser.activeIndex(lines, currentTime)
    var prevActive by androidx.compose.runtime.remember { androidx.compose.runtime.mutableIntStateOf(-1) }

    LaunchedEffect(activeIndex) {
        if (autoScroll && activeIndex >= 0 && activeIndex != prevActive) {
            delay(80)
            listState.animateScrollToItem((activeIndex - 2).coerceAtLeast(0))
        }
        prevActive = activeIndex
    }

    Column(modifier) {
        // Header
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 4.dp, vertical = 8.dp),
        ) {
            Text(
                "LRC",
                fontSize = 9.sp,
                fontWeight = FontWeight.Bold,
                color = Fp.Orange,
                modifier = Modifier
                    .clip(RoundedCornerShape(3.dp))
                    .background(Fp.OrangeLight)
                    .padding(horizontal = 6.dp, vertical = 2.dp),
            )
            Spacer(Modifier.width(8.dp))
            Text(
                "${lines.size} lines",
                fontSize = 11.sp,
                color = Fp.TextTertiary,
                fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace,
            )
            Spacer(Modifier.weight(1f))
            if (lines.isNotEmpty()) {
                Icon(
                    Icons.Filled.Fullscreen,
                    contentDescription = "Immersive mode",
                    tint = Fp.TextSecondary,
                    modifier = Modifier
                        .size(24.dp)
                        .clickable { onFullscreen() },
                )
                Spacer(Modifier.width(4.dp))
                Icon(
                    Icons.Filled.Delete,
                    contentDescription = "Remove lyrics",
                    tint = Fp.TextSecondary,
                    modifier = Modifier
                        .size(24.dp)
                        .clickable { onRemoveLrc() },
                )
            }
        }

        if (lines.isEmpty()) {
            EmptyLyrics(onUpload, onFullscreen, onFetchLyrics, fetchState)
            return
        }

        Box(
            Modifier
                .fillMaxWidth()
                .weight(1f),
            contentAlignment = Alignment.Center,
        ) {
            LazyColumn(
                state = listState,
                modifier = Modifier.fillMaxSize(),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                items(lines.size) { i ->
                    val line = lines[i]
                    val state = when {
                        i == activeIndex -> LineState.Active
                        i < activeIndex -> LineState.Past
                        else -> {
                            // distant: far ahead of active
                            if (activeIndex >= 0 && i - activeIndex > 2) LineState.Distant else LineState.Future
                        }
                    }
                    LyricsLine(line, state)
                }
            }
        }
    }
}

private enum class LineState { Distant, Future, Past, Active }

@Composable
private fun LyricsLine(line: LrcLine, state: LineState) {
    val style = when (state) {
        LineState.Active -> LineStyle(Fp.Orange, Fp.Orange.copy(alpha = 0.7f), 18.sp, FontWeight.SemiBold)
        LineState.Past -> LineStyle(Fp.TextPrimary.copy(alpha = 0.5f), Fp.TextPrimary.copy(alpha = 0.3f), 13.sp, FontWeight.Normal)
        LineState.Future -> LineStyle(Fp.TextPrimary, Color.Transparent, 13.sp, FontWeight.Normal)
        LineState.Distant -> LineStyle(Fp.TextPrimary.copy(alpha = 0.28f), Color.Transparent, 13.sp, FontWeight.Normal)
    }
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp, vertical = 10.dp),
    ) {
        if (state == LineState.Active) {
            Box(
                Modifier
                    .width(3.dp)
                    .height(24.dp)
                    .background(Fp.Orange, RoundedCornerShape(2.dp)),
            )
        } else {
            Spacer(Modifier.width(3.dp))
        }
        Text(
            formatLrcTime(line.time),
            fontSize = 10.sp,
            color = style.timeColor,
            fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace,
            textAlign = TextAlign.End,
            modifier = Modifier.width(42.dp),
        )
        Spacer(Modifier.width(12.dp))
        Text(
            line.text,
            fontSize = style.fontSize,
            fontWeight = style.weight,
            color = style.textColor,
            lineHeight = if (state == LineState.Active) 28.sp else 20.sp,
            modifier = Modifier.weight(1f),
        )
    }
}

private data class LineStyle(
    val textColor: Color,
    val timeColor: Color,
    val fontSize: androidx.compose.ui.unit.TextUnit,
    val weight: FontWeight,
)

private fun formatLrcTime(time: Double): String {
    val m = (time / 60).toInt()
    val s = (time % 60).toInt()
    return "$m:${s.toString().padStart(2, '0')}"
}

@Composable
private fun EmptyLyrics(
    onUpload: () -> Unit,
    onFullscreen: () -> Unit,
    onFetchLyrics: (() -> Unit)?,
    fetchState: com.zprolab.FreePlayer.data.FetchState,
) {
    Column(
        Modifier
            .fillMaxWidth()
            .padding(vertical = 48.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(Icons.Filled.Lyrics, contentDescription = null, tint = Fp.TextTertiary, modifier = Modifier.size(32.dp))
        Text("No synced lyrics", fontSize = 14.sp, color = Fp.TextSecondary)
        Text(
            "Upload an .lrc file to see time-synced lyrics",
            fontSize = 12.sp,
            color = Fp.TextTertiary,
            fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace,
        )
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            if (onFetchLyrics != null) {
                val label = when (fetchState) {
                    com.zprolab.FreePlayer.data.FetchState.FETCHING -> "Fetching..."
                    com.zprolab.FreePlayer.data.FetchState.FAILED -> "Found failed"
                    com.zprolab.FreePlayer.data.FetchState.NOT_FOUND -> "No lyrics found"
                    else -> "Fetch Lyrics"
                }
                Box(
                    Modifier
                        .clip(RoundedCornerShape(4.dp))
                        .border(1.dp, Fp.Orange, RoundedCornerShape(4.dp))
                        .clickable(enabled = fetchState != com.zprolab.FreePlayer.data.FetchState.FETCHING) { onFetchLyrics() }
                        .padding(horizontal = 12.dp, vertical = 7.dp),
                ) {
                    Text(label, fontSize = 12.sp, color = Fp.Orange)
                }
            }
            OutlinedButton(Fp.Orange) { onUpload() }
            Spacer(Modifier.width(6.dp))
            Icon(
                Icons.Filled.Fullscreen,
                contentDescription = "Fullscreen View",
                tint = Fp.TextSecondary,
                modifier = Modifier.size(24.dp).clickable { onFullscreen() },
            )
        }
    }
}

@Composable
private fun OutlinedButton(color: Color, onClick: () -> Unit) {
    Box(
        Modifier
            .clip(RoundedCornerShape(4.dp))
            .clickable(onClick = onClick)
            .background(Color.Transparent, RoundedCornerShape(4.dp))
            .padding(horizontal = 16.dp, vertical = 8.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Icon(Icons.Filled.Upload, contentDescription = null, tint = color, modifier = Modifier.size(14.dp))
            Text("Upload .lrc File", color = color, fontSize = 13.sp)
        }
    }
}
