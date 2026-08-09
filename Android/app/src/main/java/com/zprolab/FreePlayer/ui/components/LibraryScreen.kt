package com.zprolab.FreePlayer.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
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
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Lyrics
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.RemoveCircle
import androidx.compose.material.icons.filled.Upload
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.zprolab.FreePlayer.data.Track
import com.zprolab.FreePlayer.ui.theme.Fp
import com.zprolab.FreePlayer.util.Formatting

@Composable
fun LibraryScreen(
    tracks: List<Track>,
    onPlay: (Track, List<Track>) -> Unit,
    currentTrack: Track?,
    isPlaying: Boolean,
    sortBy: String,
    sortDir: String,
    onSort: (String) -> Unit,
    activePlaylistId: Long?,
    playlists: List<com.zprolab.FreePlayer.data.Playlist>,
    onAddToPlaylist: (Long, Long) -> Unit,
    onRemoveFromPlaylist: (Long) -> Unit,
    onCreatePlaylistForTrack: (Track) -> Unit,
    onEditTrack: (Track) -> Unit,
    onUploadLrc: (Track) -> Unit,
    onRemoveLrc: (Track) -> Unit,
    onDeleteTrack: (Long) -> Unit,
) {
    if (tracks.isEmpty()) {
        Column(
            Modifier.fillMaxSize(),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Icon(
                Icons.Filled.MusicNote,
                contentDescription = null,
                tint = Color(0xFFd0d0d4),
                modifier = Modifier.size(48.dp),
            )
            Spacer(Modifier.height(12.dp))
            Text("No tracks yet", fontSize = 15.sp, color = Fp.TextSecondary)
            Text("Import your music to start building your library.", fontSize = 13.sp, color = Fp.TextTertiary)
        }
        return
    }

    val compact = androidx.compose.ui.platform.LocalConfiguration.current.screenWidthDp < 600

    Column(Modifier.fillMaxSize()) {
        if (!compact) {
            // Full table header for tablets and desktop-sized windows.
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .background(Color.White)
                    .padding(vertical = 8.dp),
            ) {
                Box(Modifier.width(32.dp), contentAlignment = Alignment.Center) {
                    Text("#", fontSize = 10.sp, fontWeight = FontWeight.Bold, color = Fp.TextTertiary)
                }
                SortableHeader("title", "Title", sortBy, sortDir, onSort, Modifier.weight(3f).padding(end = 6.dp))
                SortableHeader("artist", "Artist", sortBy, sortDir, onSort, Modifier.weight(2f).padding(end = 6.dp))
                SortableHeader("album", "Album", sortBy, sortDir, onSort, Modifier.weight(2f).padding(end = 6.dp))
                SortableHeader("duration", "Dur.", sortBy, sortDir, onSort, Modifier.weight(0.8f).padding(end = 6.dp))
                SortableHeader("imported_at", "Added", sortBy, sortDir, onSort, Modifier.weight(1.2f).padding(end = 4.dp))
            }
        }

        LazyColumn(Modifier.weight(1f)) {
            itemsIndexed(tracks, key = { _, t -> t.id }) { index, track ->
                TrackRow(
                    index = index,
                    track = track,
                    isCurrent = currentTrack?.id == track.id,
                    isPlaying = isPlaying,
                    compact = compact,
                    playlists = playlists,
                    onPlay = { onPlay(track, tracks) },
                    onEdit = { onEditTrack(track) },
                    onAddToPlaylist = { onAddToPlaylist(it, track.id) },
                    onCreatePlaylist = { onCreatePlaylistForTrack(track) },
                    onUploadLrc = { onUploadLrc(track) },
                    onRemoveLrc = { onRemoveLrc(track) },
                    onDelete = { onDeleteTrack(track.id) },
                    onRemoveFromPlaylist = if (activePlaylistId != null) { { onRemoveFromPlaylist(track.id) } } else null,
                )
            }
        }
    }
}

@Composable
private fun SortableHeader(
    key: String,
    label: String,
    sortBy: String,
    sortDir: String,
    onSort: (String) -> Unit,
    modifier: Modifier,
) {
    val active = sortBy == key
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = modifier
            .clickable(role = androidx.compose.ui.semantics.Role.Button) { onSort(key) }
            .padding(horizontal = 8.dp, vertical = 4.dp),
    ) {
        Text(
            label,
            fontSize = 11.sp,
            fontWeight = FontWeight.Bold,
            color = if (active) Fp.Orange else Fp.TextTertiary,
        )
        Spacer(Modifier.width(4.dp))
        Text(
            if (active) (if (sortDir == "ASC") "↑" else "↓") else "↓",
            fontSize = 10.sp,
            color = if (active) Fp.Orange else Fp.TextTertiary.copy(alpha = 0.3f),
        )
    }
}

@Composable
private fun TrackRow(
    index: Int,
    track: Track,
    isCurrent: Boolean,
    isPlaying: Boolean,
    compact: Boolean,
    playlists: List<com.zprolab.FreePlayer.data.Playlist>,
    onPlay: () -> Unit,
    onEdit: () -> Unit,
    onAddToPlaylist: (Long) -> Unit,
    onCreatePlaylist: () -> Unit,
    onUploadLrc: () -> Unit,
    onRemoveLrc: () -> Unit,
    onDelete: () -> Unit,
    onRemoveFromPlaylist: (() -> Unit)?,
) {
    var menuOpen by remember { mutableStateOf(false) }
    var menuAddOpen by remember { mutableStateOf(false) }

    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .background(if (isCurrent) Fp.BlueLight else Color.Transparent)
            .combinedClickable(
                onClick = onPlay,
                onLongClick = { menuOpen = true },
            )
            .padding(vertical = 10.dp),
    ) {
        // # column: eq bars when current+playing
        Box(Modifier.width(32.dp), contentAlignment = Alignment.Center) {
            if (isCurrent && isPlaying) {
                EqualizerBars(active = true)
            } else {
                Text(
                    (index + 1).toString(),
                    fontSize = 10.sp,
                    color = if (isCurrent) Fp.Orange else Fp.TextTertiary,
                    fontFamily = FontFamily.Monospace,
                )
            }
        }
        if (compact) {
            Column(Modifier.weight(1f).padding(end = 10.dp)) {
                Text(
                    track.title,
                    fontSize = 13.sp,
                    fontWeight = if (isCurrent) FontWeight.Bold else FontWeight.Medium,
                    color = if (isCurrent) Fp.Blue else Fp.TextPrimary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    listOf(track.artist, track.album).filter { it.isNotBlank() }.joinToString(" · "),
                    fontSize = 11.sp,
                    color = Fp.TextSecondary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            track.fileFormat?.let {
                Text(
                    it.uppercase(),
                    fontSize = 8.sp,
                    fontFamily = FontFamily.Monospace,
                    color = Fp.TextTertiary,
                    modifier = Modifier
                        .clip(RoundedCornerShape(3.dp))
                        .background(Fp.BorderLight)
                        .padding(horizontal = 4.dp, vertical = 2.dp),
                )
                Spacer(Modifier.width(10.dp))
            }
            Text(
                Formatting.formatTrackDuration(track.duration),
                fontSize = 11.sp,
                color = Fp.TextSecondary,
                fontFamily = FontFamily.Monospace,
            )
            Spacer(Modifier.width(10.dp))
        } else {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.weight(3f).padding(end = 6.dp),
            ) {
                Text(
                    track.title,
                    fontSize = 12.sp,
                    fontWeight = if (isCurrent) FontWeight.Bold else FontWeight.Normal,
                    color = if (isCurrent) Fp.Blue else Fp.TextPrimary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
                track.fileFormat?.let {
                    Spacer(Modifier.width(4.dp))
                    Text(
                        it.uppercase(),
                        fontSize = 8.sp,
                        fontFamily = FontFamily.Monospace,
                        color = Fp.TextTertiary,
                        modifier = Modifier
                            .clip(RoundedCornerShape(3.dp))
                            .background(Fp.BorderLight)
                            .padding(horizontal = 3.dp, vertical = 1.dp),
                    )
                }
            }
            Text(track.artist, fontSize = 12.sp, color = Fp.TextPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(2f).padding(end = 6.dp))
            Text(track.album, fontSize = 12.sp, color = Fp.TextPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(2f).padding(end = 6.dp))
            Text(Formatting.formatTrackDuration(track.duration), fontSize = 11.sp, color = Fp.TextSecondary, fontFamily = FontFamily.Monospace, modifier = Modifier.weight(0.8f).padding(end = 6.dp))
            Text(Formatting.formatImportedAt(track.importedAt), fontSize = 11.sp, color = Fp.TextSecondary, fontFamily = FontFamily.Monospace, modifier = Modifier.weight(1.2f).padding(end = 4.dp))
            Spacer(Modifier.width(16.dp))
        }
        Icon(
            if (isCurrent) Icons.Filled.GraphicEq else Icons.Filled.PlayArrow,
            contentDescription = "Play",
            tint = if (isCurrent) Fp.Orange else Fp.TextTertiary,
            modifier = Modifier
                .size(20.dp)
                .clickable(role = androidx.compose.ui.semantics.Role.Button, onClick = onPlay),
        )
        Spacer(Modifier.width(if (compact) 12.dp else 16.dp))

        if (menuAddOpen) {
            DropdownMenu(expanded = menuAddOpen, onDismissRequest = {
                menuAddOpen = false
                menuOpen = true
            }) {
                if (playlists.isEmpty()) {
                    Text(
                        "No playlists yet",
                        fontSize = 12.sp,
                        color = Fp.TextTertiary,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                    )
                } else {
                    playlists.forEach { pl ->
                        DropdownMenuItem(
                            text = {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Icon(Icons.Filled.MusicNote, null, Modifier.size(14.dp), tint = Fp.TextSecondary)
                                    Spacer(Modifier.width(8.dp))
                                    Text(pl.name, fontSize = 14.sp)
                                }
                            },
                            onClick = { menuAddOpen = false; onAddToPlaylist(pl.id) },
                        )
                    }
                }
                androidx.compose.material3.HorizontalDivider()
                DropdownMenuItem(
                    text = { Text("New Playlist...", color = Fp.Orange) },
                    onClick = { menuAddOpen = false; onCreatePlaylist() },
                )
            }
        } else {
            DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                DropdownMenuItem(
                    text = { Text("Edit Metadata") },
                    leadingIcon = { Icon(Icons.Filled.Edit, null, Modifier.size(16.dp)) },
                    onClick = { menuOpen = false; onEdit() },
                )
                DropdownMenuItem(
                    text = { Text("Add to Playlist") },
                    leadingIcon = { Icon(Icons.Filled.Add, null, Modifier.size(16.dp)) },
                    onClick = { menuOpen = false; menuAddOpen = true },
                )
                DropdownMenuItem(
                    text = { Text("Upload Lyrics...") },
                    leadingIcon = { Icon(Icons.Filled.Upload, null, Modifier.size(16.dp)) },
                    onClick = { menuOpen = false; onUploadLrc() },
                )
                if (track.lrcPath != null) {
                    DropdownMenuItem(
                        text = { Text("Remove Lyrics") },
                        leadingIcon = { Icon(Icons.Filled.Lyrics, null, Modifier.size(16.dp)) },
                        onClick = { menuOpen = false; onRemoveLrc() },
                    )
                }
                if (onRemoveFromPlaylist != null) {
                    DropdownMenuItem(
                        text = { Text("Remove from Playlist") },
                        leadingIcon = { Icon(Icons.Filled.RemoveCircle, null, Modifier.size(16.dp)) },
                        onClick = { menuOpen = false; onRemoveFromPlaylist() },
                    )
                }
                DropdownMenuItem(
                    text = { Text("Delete Track", color = Fp.Red) },
                    leadingIcon = { Icon(Icons.Filled.Delete, null, Modifier.size(16.dp)) },
                    onClick = { menuOpen = false; onDelete() },
                )
            }
        }
    }
}
