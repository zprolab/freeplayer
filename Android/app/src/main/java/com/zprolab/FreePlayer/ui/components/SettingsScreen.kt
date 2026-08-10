package com.zprolab.FreePlayer.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
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
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Folder
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
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.zprolab.FreePlayer.ui.theme.Fp

/**
 * Port of Settings.jsx — import mode cards, library dir, playback
 * defaults, danger zone with confirm dialog.
 */
@Composable
fun SettingsScreen(
    importMode: String,
    onImportModeChange: (String) -> Unit,
    libraryDir: String,
    defaultVolume: Float,
    onDefaultVolumeChange: (Float) -> Unit,
    defaultVisualizer: String,
    onDefaultVisualizerChange: (String) -> Unit,
    onOpenEqualizer: () -> Unit,
    onResetDatabase: () -> Unit,
    acoustidKey: String,
    onAcoustidKeyChange: (String) -> Unit,
    autoFetchMeta: Boolean,
    onAutoFetchMetaChange: (Boolean) -> Unit,
    onStartBackfill: () -> Unit,
    backfillProgress: Pair<Int, Int>?,
) {
    Column(
        Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .widthIn(max = 640.dp),
        ) {
            // Import Mode
            SettingsSection("Import Mode") {
                BoxWithConstraints {
                    if (maxWidth < 560.dp) {
                        Column(verticalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
                            ModeCard("Copy Files", "Duplicate files into library directory", importMode == "copy", Modifier.fillMaxWidth()) { onImportModeChange("copy") }
                            ModeCard("Symlink", "Create symbolic links (saves disk space)", importMode == "symlink", Modifier.fillMaxWidth()) { onImportModeChange("symlink") }
                        }
                    } else {
                        Row(horizontalArrangement = Arrangement.spacedBy(16.dp), modifier = Modifier.fillMaxWidth()) {
                            ModeCard("Copy Files", "Duplicate files into library directory", importMode == "copy", Modifier.weight(1f)) { onImportModeChange("copy") }
                            ModeCard("Symlink", "Create symbolic links (saves disk space)", importMode == "symlink", Modifier.weight(1f)) { onImportModeChange("symlink") }
                        }
                    }
                }
                Spacer(Modifier.height(12.dp))
                Box(
                    Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(6.dp))
                        .background(Fp.ContentBg)
                        .border(1.dp, Fp.BorderLight, RoundedCornerShape(6.dp))
                        .clickable(onClick = onOpenEqualizer)
                        .padding(horizontal = 14.dp, vertical = 11.dp),
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text("Equalizer", fontSize = 13.sp, color = Fp.TextPrimary, fontWeight = FontWeight.Medium)
                            Text("Adjust 10 playback frequency bands", fontSize = 11.sp, color = Fp.TextSecondary)
                        }
                        Text("Open", fontSize = 12.sp, color = Fp.Orange, fontWeight = FontWeight.Medium)
                    }
                }
            }

            Spacer(Modifier.height(16.dp))

            // Library Directory
            SettingsSection("Library Directory") {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(4.dp))
                        .background(Fp.ContentBg)
                        .border(1.dp, Fp.BorderLight, RoundedCornerShape(4.dp))
                        .padding(horizontal = 12.dp, vertical = 10.dp),
                ) {
                    Icon(Icons.Filled.Folder, contentDescription = null, tint = Fp.TextTertiary, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.width(8.dp))
                    Column(Modifier.weight(1f)) {
                        Text(
                            libraryDir.ifEmpty { "No library directory set" },
                            fontSize = 12.sp,
                            color = if (libraryDir.isEmpty()) Fp.TextTertiary else Fp.TextPrimary,
                            fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace,
                            maxLines = 2,
                        )
                        Text(
                            "App default library — music is stored inside the app's own storage.",
                            fontSize = 11.sp,
                            color = Fp.TextSecondary,
                            maxLines = 3,
                            overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                        )
                    }
                }
            }

            Spacer(Modifier.height(16.dp))

            // Playback
            SettingsSection("Playback") {
                // Default volume
                Column(Modifier.fillMaxWidth().padding(vertical = 6.dp)) {
                    Text("Default Volume", fontSize = 13.sp, color = Fp.TextPrimary)
                    Text("Initial volume for new playbacks", fontSize = 11.sp, color = Fp.TextSecondary)
                    Spacer(Modifier.height(8.dp))
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        modifier = Modifier.align(Alignment.End),
                    ) {
                        Box(
                            Modifier
                                .width(120.dp)
                                .height(16.dp)
                                .pointerInput(Unit) {
                                    detectDragGestures { change, _ ->
                                        onDefaultVolumeChange((change.position.x / size.width.toFloat()).coerceIn(0f, 1f))
                                        change.consume()
                                    }
                                    detectTapGestures { offset ->
                                        onDefaultVolumeChange((offset.x / size.width.toFloat()).coerceIn(0f, 1f))
                                    }
                                },
                        ) {
                            Box(
                                Modifier
                                    .fillMaxWidth(defaultVolume)
                                    .fillMaxHeight()
                                    .background(Fp.TextPrimary),
                            )
                        }
                        Text(
                            "${(defaultVolume * 100).toInt()}%",
                            fontSize = 12.sp,
                            color = Fp.TextSecondary,
                            fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace,
                        )
                    }
                }
                Spacer(Modifier.height(12.dp))
                // Default visualizer
                BoxWithConstraints {
                    if (maxWidth < 560.dp) {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp)) {
                            Column {
                                Text("Default Visualizer", fontSize = 13.sp, color = Fp.TextPrimary)
                                Text("Visualizer mode on first run", fontSize = 11.sp, color = Fp.TextSecondary)
                            }
                            VisualizerSegments(defaultVisualizer, onDefaultVisualizerChange)
                        }
                    } else {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp),
                        ) {
                            Column(Modifier.weight(1f)) {
                                Text("Default Visualizer", fontSize = 13.sp, color = Fp.TextPrimary)
                                Text("Visualizer mode on first run", fontSize = 11.sp, color = Fp.TextSecondary)
                            }
                            VisualizerSegments(defaultVisualizer, onDefaultVisualizerChange)
                        }
                    }
                }
            }

            Spacer(Modifier.height(16.dp))


            // Online Recognition
            SettingsSection("Online Recognition") {
                var key by remember { mutableStateOf(acoustidKey) }
                var autoFetch by remember { mutableStateOf(autoFetchMeta) }
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                        Column(Modifier.weight(1f)) {
                            Text("AcoustID API Key", fontSize = 13.sp, color = Fp.TextPrimary)
                            Text("Register an app at acoustid.org (free)", fontSize = 11.sp, color = Fp.TextSecondary)
                        }
                        androidx.compose.foundation.text.BasicTextField(
                            value = key,
                            onValueChange = {
                                key = it
                                onAcoustidKeyChange(it)
                            },
                            singleLine = true,
                            textStyle = androidx.compose.ui.text.TextStyle(fontSize = 12.sp, color = Fp.TextPrimary),
                            cursorBrush = androidx.compose.ui.graphics.SolidColor(Fp.Blue),
                            modifier = Modifier
                                .width(140.dp)
                                .clip(RoundedCornerShape(4.dp))
                                .background(Fp.ContentBg)
                                .border(1.dp, Fp.BorderLight, RoundedCornerShape(4.dp))
                                .padding(horizontal = 8.dp, vertical = 6.dp),
                        )
                    }
                    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                        Column(Modifier.weight(1f)) {
                            Text("Auto-fetch missing lyrics & covers", fontSize = 13.sp, color = Fp.TextPrimary)
                            Text("Recognize songs by content while playing", fontSize = 11.sp, color = Fp.TextSecondary)
                        }
                        androidx.compose.material3.Switch(
                            checked = autoFetch,
                            onCheckedChange = {
                                autoFetch = it
                                onAutoFetchMetaChange(it)
                            },
                        )
                    }
                    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                        Column(Modifier.weight(1f)) {
                            Text("Backfill Missing Metadata", fontSize = 13.sp, color = Fp.TextPrimary)
                            Text(
                                if (backfillProgress != null) "Done \${backfillProgress!!.first}/\${backfillProgress!!.second}"
                                else "Fetch lyrics & covers for all tracks missing them",
                                fontSize = 11.sp,
                                color = Fp.TextSecondary,
                            )
                        }
                        Box(
                            Modifier
                                .clip(RoundedCornerShape(4.dp))
                                .border(1.dp, Fp.Orange, RoundedCornerShape(4.dp))
                                .clickable(onClick = onStartBackfill)
                                .padding(horizontal = 10.dp, vertical = 6.dp),
                        ) {
                            Text("Start", fontSize = 11.sp, color = Fp.Orange)
                        }
                    }
                }
            }

            Spacer(Modifier.height(16.dp))

            // Danger zone
            var confirmOpen by remember { mutableStateOf(false) }
            Column(
                Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(6.dp))
                    .background(Color.White)
                    .border(1.dp, Fp.Red, RoundedCornerShape(6.dp))
                    .padding(20.dp),
            ) {
                Text("Danger Zone", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = Fp.Red)
                Spacer(Modifier.height(10.dp))
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                    Column(Modifier.weight(1f)) {
                        Text("Reset Database", fontSize = 13.sp, color = Fp.TextPrimary)
                        Text("Delete all tracks, history, playlists and settings", fontSize = 11.sp, color = Fp.TextSecondary)
                    }
                    DangerButton("Reset...") { confirmOpen = true }
                }
            }

            if (confirmOpen) {
                ConfirmDialog(
                    title = "Reset Database",
                    message = "This will permanently delete all tracks, play history, playlists and settings. Your music files on disk are not affected. This cannot be undone.",
                    onCancel = { confirmOpen = false },
                    onConfirm = {
                        confirmOpen = false
                        onResetDatabase()
                    },
                )
            }        }
    }
}

@Composable
private fun SettingsSection(title: String, content: @Composable () -> Unit) {
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(6.dp))
            .background(Color.White)
            .padding(20.dp),
    ) {
        Text(title, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = Fp.TextPrimary)
        Spacer(Modifier.height(12.dp))
        content()
    }
}

@Composable
private fun ModeCard(label: String, hint: String, selected: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Column(
        modifier
            .clip(RoundedCornerShape(6.dp))
            .background(if (selected) Fp.OrangeLight else Color.White)
            .border(if (selected) 2.dp else 1.dp, if (selected) Fp.Orange else Fp.Border, RoundedCornerShape(6.dp))
            .clickable(onClick = onClick)
            .padding(14.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                Modifier
                    .size(20.dp)
                    .clip(CircleShape)
                    .border(2.dp, if (selected) Fp.Orange else Fp.Border, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                if (selected) {
                    Box(Modifier.size(10.dp).background(Fp.Orange, CircleShape))
                }
            }
            Spacer(Modifier.width(10.dp))
            Column {
                Text(
                    label,
                    fontSize = 13.sp,
                    fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
                    color = if (selected) Fp.Orange else Fp.TextPrimary,
                    maxLines = 1,
                    overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                )
            }
        }
        Spacer(Modifier.height(6.dp))
        Text(
            hint,
            fontSize = 11.sp,
            color = Fp.TextSecondary,
            maxLines = 2,
            overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
        )
    }
}

@Composable
private fun SecondaryButton(label: String, onClick: () -> Unit) {
    Box(
        Modifier
            .clip(RoundedCornerShape(4.dp))
            .border(1.dp, Fp.Border, RoundedCornerShape(4.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 6.dp),
    ) {
        Text(label, fontSize = 12.sp, color = Fp.TextPrimary)
    }
}

@Composable
private fun Segment(label: String, active: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Box(
        modifier
            .background(if (active) Fp.Orange else Color.White)
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 6.dp),
    ) {
        Text(label, fontSize = 12.sp, color = if (active) Color.White else Fp.TextPrimary, maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis)
    }
}

@Composable
private fun VisualizerSegments(value: String, onChange: (String) -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(4.dp))
            .border(1.dp, Fp.Border, RoundedCornerShape(4.dp)),
    ) {
        Segment("Waveform", value == "waveform", Modifier.weight(1f)) { onChange("waveform") }
        Segment("Spectrogram", value == "spectrogram", Modifier.weight(1f)) { onChange("spectrogram") }
        Segment("Off", value == "off", Modifier.weight(0.65f)) { onChange("off") }
    }
}

@Composable
private fun DangerButton(label: String, onClick: () -> Unit) {
    Box(
        Modifier
            .clip(RoundedCornerShape(4.dp))
            .border(1.dp, Fp.Red, RoundedCornerShape(4.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 6.dp),
    ) {
        Text(label, fontSize = 12.sp, color = Fp.Red)
    }
}

@Composable
fun ConfirmDialog(
    title: String,
    message: String,
    onCancel: () -> Unit,
    onConfirm: () -> Unit,
) {
    androidx.compose.ui.window.Dialog(onDismissRequest = onCancel) {
        Column(
            Modifier
                .clip(RoundedCornerShape(8.dp))
                .background(Color.White)
                .padding(24.dp),
        ) {
            Text(title, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = Fp.TextPrimary)
            Spacer(Modifier.height(12.dp))
            Text(message, fontSize = 13.sp, color = Fp.TextSecondary)
            Spacer(Modifier.height(20.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
                Spacer(Modifier.weight(1f))
                SecondaryButton("Cancel") { onCancel() }
                Box(
                    Modifier
                        .clip(RoundedCornerShape(4.dp))
                        .background(Fp.Orange)
                        .clickable(onClick = onConfirm)
                        .padding(horizontal = 12.dp, vertical = 6.dp),
                ) {
                    Text("Reset Everything", fontSize = 12.sp, color = Color.White)
                }
            }
        }
    }
}
