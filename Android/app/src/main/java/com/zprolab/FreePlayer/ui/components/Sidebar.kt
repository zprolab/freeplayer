package com.zprolab.FreePlayer.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.KeyboardArrowLeft
import androidx.compose.material.icons.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.LibraryMusic
import androidx.compose.material.icons.filled.List
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Settings
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.zprolab.FreePlayer.data.Playlist
import com.zprolab.FreePlayer.playback.View
import com.zprolab.FreePlayer.ui.theme.Fp

@Composable
fun Sidebar(
    currentView: View,
    trackCount: Int,
    playlists: List<Playlist>,
    activePlaylistId: Long?,
    width: Float,
    collapsed: Boolean,
    onToggleCollapsed: () -> Unit,
    onResize: (Float) -> Unit,
    onNavigate: (View) -> Unit,
    onImport: () -> Unit,
    onSelectPlaylist: (Long?) -> Unit,
    onCreatePlaylist: () -> Unit,
    onRenamePlaylist: (Playlist) -> Unit,
    onEditPlaylist: (Playlist) -> Unit,
    onDeletePlaylist: (Playlist) -> Unit,
) {
    Box(
        Modifier
            .width(if (collapsed) 56.dp else width.dp)
            .fillMaxHeight()
            .background(Fp.SidebarBg)
            .border(1.dp, Fp.BorderDark, RoundedCornerShape(0.dp))
    ) {
        Column(Modifier.fillMaxHeight().padding(top = 24.dp)) {
            if (!collapsed) {
                // Logo
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(horizontal = 16.dp)) {
                    LogoBadge()
                    Spacer(Modifier.width(10.dp))
                    Text("FreePlayer", color = Color(0xFFd4d4d8), fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                }
            } else {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.Center,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    LogoBadge()
                }
            }

            Spacer(Modifier.height(24.dp))

            // Navigation
            NavItem(
                Icons.Filled.LibraryMusic, "Library",
                currentView == View.LIBRARY && activePlaylistId == null,
                collapsed,
            ) {
                onSelectPlaylist(null)
                onNavigate(View.LIBRARY)
            }
            NavItem(Icons.Filled.PlayArrow, "Now Playing", currentView == View.NOW_PLAYING, collapsed) { onNavigate(View.NOW_PLAYING) }
            NavItem(Icons.Filled.BarChart, "Statistics", currentView == View.STATS, collapsed) { onNavigate(View.STATS) }
            NavItem(Icons.Filled.Settings, "Settings", currentView == View.SETTINGS, collapsed) { onNavigate(View.SETTINGS) }

            if (!collapsed) {
                Spacer(Modifier.height(20.dp))

                // Playlists header
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp),
                ) {
                    Text(
                        "PLAYLISTS",
                        color = Color(0xFF8c8c93),
                        fontSize = 10.sp,
                        fontWeight = FontWeight.SemiBold,
                        letterSpacing = 0.08f.sp,
                        modifier = Modifier.weight(1f),
                    )
                    Icon(
                        Icons.Filled.Add,
                        contentDescription = "New Playlist",
                        tint = Color(0xFF8c8c93),
                        modifier = Modifier
                            .size(20.dp)
                            .clickable { onCreatePlaylist() },
                    )
                }

                Spacer(Modifier.height(8.dp))

                // All Tracks (fixed)
                PlaylistRow(
                    name = "All Tracks",
                    badge = trackCount.toString(),
                    selected = activePlaylistId == null && currentView == View.LIBRARY,
                    onSelect = { onSelectPlaylist(null); onNavigate(View.LIBRARY) },
                    onRename = {},
                    onEdit = {},
                    onDelete = {},
                )

                Column(Modifier.verticalScroll(rememberScrollState()).weight(1f)) {
                    playlists.forEach { pl ->
                        PlaylistRow(
                            name = pl.name,
                            badge = null,
                            selected = activePlaylistId == pl.id,
                            onSelect = { onSelectPlaylist(pl.id); onNavigate(View.LIBRARY) },
                            onRename = { onRenamePlaylist(pl) },
                            onEdit = { onEditPlaylist(pl) },
                            onDelete = { onDeletePlaylist(pl) },
                        )
                    }
                }
            }

            if (collapsed) {
                Spacer(Modifier.weight(1f))
            }

            // Footer: Import Music
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.Center,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(10.dp)
                    .clip(RoundedCornerShape(4.dp))
                    .clickable { onImport() }
                    .padding(vertical = 9.dp),
            ) {
                Icon(Icons.Filled.Upload, contentDescription = null, tint = Color(0xFFceced0), modifier = Modifier.size(15.dp))
                if (!collapsed) {
                    Spacer(Modifier.width(8.dp))
                    Text("Import Music", color = Color(0xFFceced0), fontSize = 13.sp)
                }
            }

            // Collapse / expand toggle
            if (collapsed) {
                Spacer(Modifier.height(4.dp))
                Box(
                    Modifier
                        .align(Alignment.CenterHorizontally)
                        .clip(RoundedCornerShape(4.dp))
                        .clickable { onToggleCollapsed() }
                        .padding(vertical = 10.dp, horizontal = 16.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        Icons.Filled.KeyboardArrowRight,
                        contentDescription = "Expand sidebar",
                        tint = Color(0xFF8c8c93),
                        modifier = Modifier.size(18.dp),
                    )
                }
            }
            if (!collapsed) {
                // Preserve the Android adaptation without adding a text-heavy footer.
                Box(
                    Modifier
                        .align(Alignment.CenterHorizontally)
                        .clip(RoundedCornerShape(4.dp))
                        .clickable { onToggleCollapsed() }
                        .padding(vertical = 5.dp, horizontal = 16.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        Icons.Filled.KeyboardArrowLeft,
                        contentDescription = "Collapse sidebar",
                        tint = Color(0xFF8c8c93),
                        modifier = Modifier.size(16.dp),
                    )
                }
            }
        }

        // Resize handle (visible when expanded)
        if (!collapsed) {
            Box(
                Modifier
                    .align(Alignment.CenterEnd)
                    .width(6.dp)
                    .fillMaxHeight()
                    .pointerInput(Unit) {
                        detectHorizontalDragGestures { change, dragAmount ->
                            onResize((width + dragAmount / density).coerceIn(MIN_WIDTH, MAX_WIDTH))
                            change.consume()
                        }
                    },
            ) {
            }
        }
    }
}

private const val MIN_WIDTH = 120f
private const val MAX_WIDTH = 320f

@Composable
private fun LogoBadge() {
    Box(
        Modifier
            .size(22.dp)
            .background(Color.Transparent),
        contentAlignment = Alignment.Center,
    ) {
        // orange ring + center dot
        Box(
            Modifier
                .size(22.dp)
                .border(2.dp, Fp.Orange, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Box(Modifier.size(6.dp).background(Fp.Orange, CircleShape))
        }
    }
}

@Composable
private fun NavItem(icon: ImageVector, label: String, active: Boolean, collapsed: Boolean, onClick: () -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = if (collapsed) Arrangement.Center else Arrangement.Start,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = if (collapsed) 0.dp else 12.dp)
            .clip(RoundedCornerShape(4.dp))
            .background(if (active) Fp.SidebarActive else Color.Transparent)
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 8.dp),
    ) {
        Icon(
            icon,
            contentDescription = label,
            tint = if (active) Fp.Orange else Color(0xFF9a9aa2),
            modifier = Modifier.size(18.dp),
        )
        if (!collapsed) {
            Spacer(Modifier.width(10.dp))
            Text(
                label,
                color = if (active) Color.White else Color(0xFF9a9aa2),
                fontSize = 13.sp,
            )
        }
    }
}

@Composable
private fun PlaylistRow(
    name: String,
    badge: String?,
    selected: Boolean,
    onSelect: () -> Unit,
    onRename: () -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
) {
    var menuOpen by remember { mutableStateOf(false) }

    Box {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp)
                .clip(RoundedCornerShape(4.dp))
                .background(if (selected) Fp.SidebarActive else Color.Transparent)
                .combinedClickable(
                    onClick = onSelect,
                    onLongClick = { menuOpen = true },
                )
                .padding(horizontal = 12.dp, vertical = 7.dp),
        ) {
            Icon(
                Icons.Filled.MusicNote,
                contentDescription = null,
                tint = if (selected) Fp.Orange else Color(0xFF8c8c93),
                modifier = Modifier.size(15.dp),
            )
            Spacer(Modifier.width(10.dp))
            Text(
                name,
                color = if (selected) Color.White else Color(0xFFb8b8c0),
                fontSize = 13.sp,
                maxLines = 1,
                modifier = Modifier.weight(1f),
            )
            if (badge != null) {
                Box(
                    Modifier
                        .clip(RoundedCornerShape(8.dp))
                        .background(Color(0xFF1d1e22))
                        .padding(horizontal = 6.dp, vertical = 1.dp),
                ) {
                    Text(badge, color = Color(0xFF8c8c93), fontSize = 11.sp, fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace)
                }
            }
        }

        DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
            DropdownMenuItem(
                text = { Text("Rename") },
                leadingIcon = { Icon(Icons.Filled.Edit, null, Modifier.size(16.dp)) },
                onClick = { menuOpen = false; onRename() },
            )
            DropdownMenuItem(
                text = { Text("Edit Tracks") },
                leadingIcon = { Icon(Icons.Filled.List, null, Modifier.size(16.dp)) },
                onClick = { menuOpen = false; onEdit() },
            )
            DropdownMenuItem(
                text = { Text("Delete", color = Fp.Red) },
                leadingIcon = { Icon(Icons.Filled.Delete, null, Modifier.size(16.dp)) },
                onClick = { menuOpen = false; onDelete() },
            )
        }
    }
}
