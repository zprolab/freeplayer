package com.zprolab.FreePlayer.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Search
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
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import com.zprolab.FreePlayer.data.Playlist
import com.zprolab.FreePlayer.data.Track
import com.zprolab.FreePlayer.ui.theme.Fp
import com.zprolab.FreePlayer.util.Formatting

/**
 * Port of PlaylistModal.jsx — create (name + description + TrackPicker),
 * rename (name only), edit (TrackPicker only).
 */
@Composable
fun PlaylistModal(
    mode: String,
    playlist: Playlist?,
    allTracks: List<Track>,
    onClose: () -> Unit,
    onCreate: (name: String, description: String?, trackIds: List<Long>?) -> Unit,
    onRename: (id: Long, name: String) -> Unit,
    onUpdateTracks: (id: Long, trackIds: List<Long>) -> Unit,
    loadExistingTrackIds: suspend (playlistId: Long) -> List<Long> = { emptyList() },
) {
    var name by remember { mutableStateOf(playlist?.name ?: "") }
    var description by remember { mutableStateOf(playlist?.description ?: "") }
    var selectedIds by remember { mutableStateOf<Set<Long>>(emptySet()) }
    var loadingTracks by remember { mutableStateOf(mode == "edit") }

    LaunchedEffect(mode, playlist?.id) {
        if (mode == "edit" && playlist != null) {
            loadingTracks = true
            // Preload current playlist tracks so saving doesn't wipe them
            // (web version pre-selects existing tracks).
            val existing = loadExistingTrackIds(playlist.id)
            selectedIds = existing.toSet()
            loadingTracks = false
        }
    }

    val canSubmit = mode == "edit" || name.isNotBlank()

    Dialog(onDismissRequest = onClose) {
        Column(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(8.dp))
                .background(Color.White)
                .padding(24.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    when (mode) {
                        "create" -> "New Playlist"
                        "rename" -> "Rename Playlist"
                        else -> "Edit Playlist"
                    },
                    fontSize = 16.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = Fp.TextPrimary,
                )
                if (mode == "edit" && playlist != null) {
                    Text(" — ${playlist.name}", fontSize = 12.sp, color = Fp.TextSecondary)
                }
                Spacer(Modifier.weight(1f))
                Icon(Icons.Filled.Close, contentDescription = "Close", tint = Fp.TextTertiary, modifier = Modifier.size(18.dp).clickable { onClose() })
            }
            Spacer(Modifier.height(16.dp))

            if (mode != "edit") {
                TextField("Name", name, "My Playlist") { name = it }
                if (mode == "create") {
                    Spacer(Modifier.height(10.dp))
                    TextField("Description (optional)", description, "A few words about this playlist...") { description = it }
                }
                Spacer(Modifier.height(16.dp))
            }

            if (mode != "rename") {
                TrackPicker(
                    tracks = allTracks,
                    selectedIds = selectedIds,
                    onToggle = { id -> selectedIds = if (id in selectedIds) selectedIds - id else selectedIds + id },
                )
                Spacer(Modifier.height(16.dp))
            }

            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
                Spacer(Modifier.weight(1f))
                SecondaryButton("Cancel") { onClose() }
                PrimaryButton(
                    when (mode) {
                        "create" -> "Create"
                        "rename" -> "Rename"
                        else -> "Save"
                    },
                    enabled = canSubmit,
                ) {
                    when (mode) {
                        "create" -> onCreate(name, description.ifBlank { null }, selectedIds.toList())
                        "rename" -> playlist?.let { onRename(it.id, name) }
                        else -> playlist?.let { onUpdateTracks(it.id, selectedIds.toList()) }
                    }
                    onClose()
                }
            }
        }
    }
}

/**
 * Port of TrackPicker.jsx — searchable multi-select list.
 */
@Composable
fun TrackPicker(
    tracks: List<Track>,
    selectedIds: Set<Long>,
    onToggle: (Long) -> Unit,
) {
    var query by remember { mutableStateOf("") }
    val filtered = if (query.isBlank()) {
        tracks
    } else {
        tracks.filter {
            it.title.contains(query, ignoreCase = true) ||
                it.artist.contains(query, ignoreCase = true) ||
                it.album.contains(query, ignoreCase = true)
        }
    }
    val allFilteredSelected = filtered.isNotEmpty() && filtered.all { it.id in selectedIds }

    Column(Modifier.fillMaxWidth()) {
        Text(
            "SELECT TRACKS",
            fontSize = 11.sp,
            fontWeight = FontWeight.SemiBold,
            color = Fp.TextTertiary,
            letterSpacing = 0.08f.sp,
        )
        Spacer(Modifier.height(8.dp))
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(4.dp))
                    .background(Fp.ContentBg)
                    .border(1.dp, Fp.BorderLight, RoundedCornerShape(4.dp))
                    .padding(horizontal = 8.dp, vertical = 6.dp),
            ) {
                Icon(Icons.Filled.Search, contentDescription = null, tint = Fp.TextTertiary, modifier = Modifier.size(14.dp))
                Spacer(Modifier.width(6.dp))
                BasicTextField(
                    value = query,
                    onValueChange = { query = it },
                    singleLine = true,
                    textStyle = TextStyle(fontSize = 12.sp, color = Fp.TextPrimary),
                    cursorBrush = SolidColor(Fp.Blue),
                    modifier = Modifier.weight(1f),
                )
            }
            Spacer(Modifier.width(10.dp))
            Box(
                Modifier
                    .clip(RoundedCornerShape(4.dp))
                    .border(1.dp, Fp.Border, RoundedCornerShape(4.dp))
                    .clickable {
                        if (allFilteredSelected) {
                            filtered.forEach { onToggle(it.id) }
                        } else {
                            filtered.forEach { if (it.id !in selectedIds) onToggle(it.id) }
                        }
                    }
                    .padding(horizontal = 10.dp, vertical = 5.dp),
            ) {
                Text(if (allFilteredSelected) "Clear" else "Select All", fontSize = 11.sp, color = Fp.TextPrimary)
            }
            Spacer(Modifier.width(8.dp))
            Text(
                "${selectedIds.size} selected",
                fontSize = 11.sp,
                color = Fp.Blue,
                fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace,
                modifier = Modifier
                    .clip(RoundedCornerShape(8.dp))
                    .background(Fp.BlueLight)
                    .padding(horizontal = 8.dp, vertical = 2.dp),
            )
        }
        Spacer(Modifier.height(8.dp))

        if (tracks.isEmpty()) {
            Text("No tracks in library", fontSize = 12.sp, color = Fp.TextTertiary, modifier = Modifier.padding(16.dp))
        } else if (filtered.isEmpty()) {
            Text("No tracks match your search", fontSize = 12.sp, color = Fp.TextTertiary, modifier = Modifier.padding(16.dp))
        } else {
            LazyColumn(Modifier.fillMaxWidth().height(300.dp)) {
                itemsIndexed(filtered, key = { _, t -> t.id }) { _, t ->
                    val checked = t.id in selectedIds
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(if (checked) Fp.BlueLight else Color.Transparent)
                            .clickable { onToggle(t.id) }
                            .padding(horizontal = 8.dp, vertical = 8.dp),
                    ) {
                        CheckBox(checked) { onToggle(t.id) }
                        Spacer(Modifier.width(8.dp))
                        Text(t.title, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = Fp.TextPrimary, maxLines = 1, modifier = Modifier.weight(2f))
                        Spacer(Modifier.width(8.dp))
                        Text(t.artist, fontSize = 12.sp, color = Fp.TextSecondary, maxLines = 1, modifier = Modifier.weight(1.3f))
                        Spacer(Modifier.width(8.dp))
                        Text(t.album, fontSize = 12.sp, color = Fp.TextSecondary, maxLines = 1, modifier = Modifier.weight(1.3f))
                        Spacer(Modifier.width(8.dp))
                        Text(Formatting.formatTrackDuration(t.duration), fontSize = 11.sp, color = Fp.TextTertiary, fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace)
                    }
                }
            }
        }
    }
}

@Composable
private fun CheckBox(checked: Boolean, onToggle: () -> Unit) {
    Box(
        Modifier
            .size(16.dp)
            .clip(RoundedCornerShape(3.dp))
            .background(if (checked) Fp.Blue else Color.White)
            .border(1.dp, if (checked) Fp.Blue else Fp.Border, RoundedCornerShape(3.dp))
            .clickable(onClick = onToggle),
        contentAlignment = Alignment.Center,
    ) {
        if (checked) {
            Text("✓", fontSize = 10.sp, color = Color.White, fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
private fun TextField(label: String, value: String, placeholder: String, onChange: (String) -> Unit) {
    Column {
        Text(label, fontSize = 12.sp, color = Fp.TextSecondary)
        Spacer(Modifier.height(4.dp))
        Box(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(4.dp))
                .background(Fp.ContentBg)
                .border(1.dp, Fp.BorderLight, RoundedCornerShape(4.dp))
                .padding(horizontal = 10.dp, vertical = 8.dp),
        ) {
            if (value.isEmpty()) {
                Text(placeholder, fontSize = 13.sp, color = Fp.TextTertiary)
            }
            BasicTextField(
                value = value,
                onValueChange = onChange,
                singleLine = true,
                textStyle = TextStyle(fontSize = 13.sp, color = Fp.TextPrimary),
                cursorBrush = SolidColor(Fp.Blue),
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

@Composable
private fun SecondaryButton(label: String, onClick: () -> Unit) {
    Box(
        Modifier
            .clip(RoundedCornerShape(4.dp))
            .border(1.dp, Fp.Border, RoundedCornerShape(4.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 7.dp),
    ) {
        Text(label, fontSize = 12.sp, color = Fp.TextPrimary)
    }
}

@Composable
private fun PrimaryButton(label: String, enabled: Boolean = true, onClick: () -> Unit) {
    Box(
        Modifier
            .clip(RoundedCornerShape(4.dp))
            .background(if (enabled) Fp.Orange else Fp.Border)
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 7.dp),
    ) {
        Text(label, fontSize = 12.sp, color = Color.White, fontWeight = FontWeight.Medium)
    }
}
