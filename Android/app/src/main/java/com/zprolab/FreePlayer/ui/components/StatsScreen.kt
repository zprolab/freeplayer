package com.zprolab.FreePlayer.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.zprolab.FreePlayer.data.DailyStat
import com.zprolab.FreePlayer.data.ListeningStats
import com.zprolab.FreePlayer.data.PlayHistoryEntry
import com.zprolab.FreePlayer.ui.theme.Fp
import com.zprolab.FreePlayer.util.Formatting

/**
 * Port of Stats.jsx — overview cards, top tracks/artists tables,
 * 14-day daily chart, recent plays.
 */
@Composable
fun StatsScreen(
    loadStats: (onResult: (ListeningStats) -> Unit) -> Unit,
    loadHistory: (limit: Int, onResult: (List<PlayHistoryEntry>) -> Unit) -> Unit,
) {
    var stats by remember { mutableStateOf<ListeningStats?>(null) }
    var history by remember { mutableStateOf<List<PlayHistoryEntry>?>(null) }

    LaunchedEffect(Unit) {
        loadStats { stats = it }
        loadHistory(30) { history = it }
    }

    if (stats == null || history == null) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            LoadingSpinner()
        }
        return
    }

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
    ) {
        val s = stats!!

        // 3 overview cards (stack in narrow content area)
        BoxWithConstraints(Modifier.fillMaxWidth()) {
            if (maxWidth < 700.dp) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
                    StatCard(Icons.Filled.Schedule, Fp.Orange, Formatting.formatDurationLong(s.totalTime), "Total Listening Time", Modifier.fillMaxWidth())
                    StatCard(Icons.Filled.PlayArrow, Fp.Blue, s.totalPlays.toString(), "Total Plays", Modifier.fillMaxWidth())
                    StatCard(Icons.Filled.MusicNote, Fp.Green, s.uniqueTracksPlayed.toString(), "Unique Tracks", Modifier.fillMaxWidth())
                }
            } else {
                Row(horizontalArrangement = Arrangement.spacedBy(16.dp), modifier = Modifier.fillMaxWidth()) {
                    StatCard(Icons.Filled.Schedule, Fp.Orange, Formatting.formatDurationLong(s.totalTime), "Total Listening Time", Modifier.weight(1f))
                    StatCard(Icons.Filled.PlayArrow, Fp.Blue, s.totalPlays.toString(), "Total Plays", Modifier.weight(1f))
                    StatCard(Icons.Filled.MusicNote, Fp.Green, s.uniqueTracksPlayed.toString(), "Unique Tracks", Modifier.weight(1f))
                }
            }
        }

        Spacer(Modifier.height(20.dp))

        // two-column tables (stack in narrow content area)
        BoxWithConstraints(Modifier.fillMaxWidth()) {
            if (maxWidth < 640.dp) {
                Column(verticalArrangement = Arrangement.spacedBy(20.dp), modifier = Modifier.fillMaxWidth()) {
                    DataTable(
                        title = "Most Played Tracks",
                        header = listOf("#", "Title", "Artist", "Plays", "Time"),
                        rows = s.topTracks.map { listOf(it.title, it.artist, it.playCount.toString(), Formatting.formatDurationLong(it.totalListenTime)) },
                        modifier = Modifier.fillMaxWidth(),
                    )
                    DataTable(
                        title = "Top Artists",
                        header = listOf("#", "Artist", "Plays", "Time"),
                        rows = s.topArtists.map { listOf(it.artist, it.playCount.toString(), Formatting.formatDurationLong(it.totalListenTime)) },
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            } else {
                Row(horizontalArrangement = Arrangement.spacedBy(20.dp), modifier = Modifier.fillMaxWidth()) {
                    DataTable(
                        title = "Most Played Tracks",
                        header = listOf("#", "Title", "Artist", "Plays", "Time"),
                        rows = s.topTracks.map { listOf(it.title, it.artist, it.playCount.toString(), Formatting.formatDurationLong(it.totalListenTime)) },
                        modifier = Modifier.weight(1f),
                    )
                    DataTable(
                        title = "Top Artists",
                        header = listOf("#", "Artist", "Plays", "Time"),
                        rows = s.topArtists.map { listOf(it.artist, it.playCount.toString(), Formatting.formatDurationLong(it.totalListenTime)) },
                        modifier = Modifier.weight(1f),
                    )
                }
            }
        }

        Spacer(Modifier.height(20.dp))

        // daily chart (last 14 days, oldest first)
        DailyChartCard(s.dailyStats)

        Spacer(Modifier.height(20.dp))

        // recent plays
        DataTable(
            title = "Recent Plays",
            header = listOf("Title", "Artist", "Started", "Duration", "%"),
            rows = history!!.map {
                listOf(it.title, it.artist, Formatting.formatStartedAt(it.startedAt), Formatting.formatDurationLong(it.durationSeconds), "${it.playPercentage.toInt()}%")
            },
            modifier = Modifier.fillMaxWidth(),
            emptyText = "No play history yet.",
        )
        Spacer(Modifier.height(24.dp))
    }
}

@Composable
private fun StatCard(icon: androidx.compose.ui.graphics.vector.ImageVector, color: Color, value: String, label: String, modifier: Modifier) {
    BoxWithConstraints(modifier = modifier.clip(RoundedCornerShape(6.dp)).background(Color.White).padding(20.dp)) {
        if (maxWidth < 200.dp) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Box(
                    Modifier
                        .size(36.dp)
                        .clip(RoundedCornerShape(6.dp))
                        .background(color.copy(alpha = 0.08f)),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(icon, contentDescription = null, tint = color, modifier = Modifier.size(18.dp))
                }
                Spacer(Modifier.height(8.dp))
                Text(value, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, color = Fp.TextPrimary, fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace)
                Spacer(Modifier.height(2.dp))
                Text(label, fontSize = 11.sp, color = Fp.TextSecondary, maxLines = 2, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            }
        } else {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    Modifier
                        .size(40.dp)
                        .clip(RoundedCornerShape(6.dp))
                        .background(color.copy(alpha = 0.08f)),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(icon, contentDescription = null, tint = color, modifier = Modifier.size(20.dp))
                }
                Spacer(Modifier.width(14.dp))
                Column {
                    Text(value, fontSize = 22.sp, fontWeight = FontWeight.SemiBold, color = Fp.TextPrimary, fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace)
                    Text(label, fontSize = 12.sp, color = Fp.TextSecondary, maxLines = 2)
                }
            }
        }
    }
}

@Composable
private fun DataTable(
    title: String,
    header: List<String>,
    rows: List<List<String>>,
    modifier: Modifier,
    emptyText: String = "No play data yet.",
) {
    Column(modifier.clip(RoundedCornerShape(6.dp)).background(Color.White)) {
        Text(
            title,
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold,
            color = Fp.TextPrimary,
            modifier = Modifier.padding(16.dp),
        )
        Box(Modifier.fillMaxWidth().height(1.dp).background(Fp.BorderLight))
        if (rows.isEmpty()) {
            Text(
                emptyText,
                fontSize = 13.sp,
                color = Fp.TextTertiary,
                modifier = Modifier.padding(vertical = 40.dp, horizontal = 20.dp),
            )
        } else {            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 7.dp),
            ) {
                header.forEachIndexed { i, h ->
                    Text(
                        h.uppercase(),
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold,
                        color = Fp.TextTertiary,
                        modifier = Modifier
                            .weight(if (i == header.size - 1) 0.8f else if (i == 0) 0.4f else 1.2f)
                            .padding(end = 8.dp),
                    )
                }
            }
            rows.forEachIndexed { i, row ->
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 7.dp),
                ) {
                    row.forEachIndexed { j, cell ->
                        Text(
                            cell,
                            fontSize = 12.sp,
                            color = if (i == 0) Fp.TextPrimary else Fp.TextSecondary,
                            maxLines = 1,
                            overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                            modifier = Modifier
                                .weight(if (j == row.size - 1) 0.8f else if (j == 0) 0.4f else 1.2f)
                                .padding(end = 8.dp),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun DailyChartCard(dailyStats: List<DailyStat>) {
    // last 14 days, oldest -> newest (port: slice(0,14).reverse())
    val days = dailyStats.take(14).reversed()
    val maxTime = (days.maxOfOrNull { it.totalTime } ?: 0.0).coerceAtLeast(0.0001)

    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(6.dp)).background(Color.White)) {
        Text(
            "Listening History (30 days)",
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold,
            color = Fp.TextPrimary,
            modifier = Modifier.padding(16.dp),
        )
        Box(Modifier.fillMaxWidth().height(1.dp).background(Fp.BorderLight))
        if (days.isEmpty()) {
            Text("No play data yet.", fontSize = 13.sp, color = Fp.TextTertiary, modifier = Modifier.padding(vertical = 40.dp, horizontal = 20.dp))
        } else {
            Row(
                verticalAlignment = Alignment.Bottom,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                modifier = Modifier
                    .fillMaxWidth()
                    .height(160.dp)
                    .padding(20.dp, 20.dp, 20.dp, 4.dp),
            ) {
                days.forEach { d ->
                    val h = ((d.totalTime / maxTime) * 136.0).toFloat().coerceAtLeast(3f)
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        modifier = Modifier.weight(1f),
                    ) {
                        Box(
                            Modifier
                                .fillMaxWidth()
                                .height(h.dp)
                                .clip(RoundedCornerShape(topStart = 4.dp, topEnd = 4.dp))
                                .background(Fp.Blue)
                                .clickable { },
                        )
                        Spacer(Modifier.height(6.dp))
                        Text(shortDate(d.date), fontSize = 9.sp, color = Fp.TextTertiary, fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace)
                    }
                }
            }
        }
    }
}

private fun shortDate(date: String): String {
    val parts = date.split("-")
    if (parts.size != 3) return date
    val months = listOf("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")
    val month = parts[1].toIntOrNull()?.let { months.getOrNull(it - 1) } ?: return date
    return "$month ${parts[2].toIntOrNull() ?: parts[2]}"
}
