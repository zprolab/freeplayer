package com.zprolab.FreePlayer.ui.components

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.FileCopy
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.zprolab.FreePlayer.import.ImportManager
import com.zprolab.FreePlayer.import.ImportSource
import com.zprolab.FreePlayer.ui.theme.Fp
import kotlinx.coroutines.launch

/**
 * Port of ImportModal.jsx — 4-step wizard:
 * Select Source -> Scan -> Review -> Import (+ done/error states).
 */
@Composable
fun ImportModal(
    importMode: String,
    libraryDir: String,
    onClose: () -> Unit,
    onComplete: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    val appContext = androidx.compose.ui.platform.LocalContext.current.applicationContext
    var step by remember { mutableStateOf("select-source") }
    var sourceDirName by remember { mutableStateOf<String?>(null) }
    var files by remember { mutableStateOf<List<ImportSource>>(emptyList()) }
    var imported by remember { mutableStateOf(0) }
    var skipped by remember { mutableStateOf(0) }
    var errors by remember { mutableStateOf<List<Pair<String, String>>>(emptyList()) }
    // The library always lives in the app default directory; initialize it
    // on first open so the review step can show a real path.
    val defaultLibraryDir = remember { ImportManager.libraryDir(appContext) }
    val displayLibraryDir = libraryDir.ifEmpty { defaultLibraryDir }

    val treePicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        if (uri != null) {
            sourceDirName = uri.lastPathSegment?.substringAfter(":") ?: "Music"
            step = "scanning"
            scope.launch {
                val found = ImportManager.scanTree(appContext, uri)
                files = found
                step = if (found.isEmpty()) "error" else "review"
                if (found.isEmpty()) {
                    errors = listOf("No audio files found" to "This folder contains no supported audio files (mp3, flac, m4a, aac, ogg, wav, opus).")
                }
            }
        } else {
            onClose()
        }
    }

    fun startImport() {
        step = "importing"
        scope.launch {
            val result = ImportManager.importFiles(appContext, files, importMode)
            imported = result.imported
            skipped = result.skipped
            errors = result.errors
            step = if (imported == 0 && errors.isNotEmpty()) "error" else "done"
        }
    }

    Dialog(
        onDismissRequest = {
            if (step != "importing") onClose()
        },
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp)
                .widthIn(max = 640.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(Color.White)
                .padding(24.dp),
        ) {
            // Header + step indicator
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Import Music", fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = Fp.TextPrimary)
                Spacer(Modifier.weight(1f))
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier
                        .clip(RoundedCornerShape(10.dp))
                        .background(Fp.GreenLight)
                        .padding(horizontal = 8.dp, vertical = 3.dp),
                ) {
                    Icon(
                        Icons.Filled.FileCopy,
                        contentDescription = null,
                        tint = Fp.Green,
                        modifier = Modifier.size(12.dp),
                    )
                    Spacer(Modifier.width(4.dp))
                    Text(
                        "Copy Mode",
                        fontSize = 10.sp,
                        color = Fp.Green,
                        fontWeight = FontWeight.Medium,
                    )
                }
                if (step != "importing") {
                    Spacer(Modifier.width(8.dp))
                    Icon(Icons.Filled.Close, contentDescription = "Close", tint = Fp.TextTertiary, modifier = Modifier.size(18.dp).clickable { onClose() })
                }
            }
            Spacer(Modifier.height(14.dp))

            // Step indicator (Select Source / Scan / Review / Import)
            val stepOrder = listOf("select-source", "scanning", "review", "importing")
            val currentIdx = stepOrder.indexOf(step).coerceAtLeast(0)
            Row(
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                verticalAlignment = Alignment.Top,
                modifier = Modifier.fillMaxWidth(),
            ) {
                listOf("Select Source", "Scan", "Review", "Import").forEachIndexed { i, label ->
                    val active = currentIdx >= i
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        modifier = Modifier.weight(1f),
                    ) {
                        // Desktop style: plain step dot (no number)
                        Box(
                            Modifier
                                .size(10.dp)
                                .clip(CircleShape)
                                .background(if (active) Fp.Orange else Fp.BorderLight),
                        )
                        Spacer(Modifier.height(6.dp))
                        Text(
                            label,
                            fontSize = 10.sp,
                            color = if (active) Fp.Orange else Fp.TextTertiary,
                            maxLines = 2,
                            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                        )
                    }
                }
            }
            Spacer(Modifier.height(18.dp))

            when (step) {
                "select-source" -> {
                    Text("Choose a folder containing music files.", fontSize = 13.sp, color = Fp.TextPrimary)
                    Spacer(Modifier.height(8.dp))
                    Text(
                        "Files will be copied into the app's default library under Artist/Album folders.",
                        fontSize = 12.sp,
                        color = Fp.TextSecondary,
                    )
                    Spacer(Modifier.height(18.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
                        Spacer(Modifier.weight(1f))
                        SecondaryButton("Cancel") { onClose() }
                        PrimaryButton("Choose Folder") { treePicker.launch(null) }
                    }
                }
                "scanning" -> {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        LoadingSpinner(Modifier.size(20.dp))
                        Spacer(Modifier.width(10.dp))
                        Text("Scanning ${sourceDirName ?: "..."}...", fontSize = 13.sp, color = Fp.TextPrimary)
                    }
                }
                "review" -> {
                    // Summary
                    Column(
                        Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(6.dp))
                            .background(Fp.ContentBg)
                            .padding(12.dp),
                    ) {
                        SummaryRow("Source", sourceDirName ?: "")
                        SummaryRow("Library", displayLibraryDir)
                        Row {
                            Text("Files found", fontSize = 11.sp, color = Fp.TextSecondary)
                            Spacer(Modifier.weight(1f))
                            Text(
                                files.size.toString(),
                                fontSize = 11.sp,
                                color = Fp.Blue,
                                fontWeight = FontWeight.Bold,
                                fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace,
                            )
                        }
                    }
                    Spacer(Modifier.height(12.dp))
                    Text("Files to import", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Fp.TextPrimary)
                    Spacer(Modifier.height(6.dp))
                    LazyColumn(Modifier.fillMaxWidth().height(160.dp)) {
                        items(files.take(20)) { f ->
                            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(vertical = 3.dp)) {
                                Icon(Icons.Filled.MusicNote, contentDescription = null, tint = Fp.TextTertiary, modifier = Modifier.size(13.dp))
                                Spacer(Modifier.width(6.dp))
                                Text(f.relativePath, fontSize = 11.sp, color = Fp.TextPrimary, fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace, maxLines = 1)
                            }
                        }
                        if (files.size > 20) {
                            item {
                                Text(
                                    "+ ${files.size - 20} more files",
                                    fontSize = 11.sp,
                                    color = Fp.TextTertiary,
                                    fontStyle = androidx.compose.ui.text.font.FontStyle.Italic,
                                )
                            }
                        }
                    }
                    Spacer(Modifier.height(16.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
                        SecondaryButton("Back") {
                            files = emptyList()
                            step = "select-source"
                        }
                        Spacer(Modifier.weight(1f))
                        SecondaryButton("Cancel") { onClose() }
                        PrimaryButton("Import ${files.size} Files", enabled = files.isNotEmpty()) { startImport() }
                    }
                }
                "importing" -> {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        LoadingSpinner(Modifier.size(20.dp))
                        Spacer(Modifier.width(10.dp))
                        Text("Importing tracks... This may take a moment.", fontSize = 13.sp, color = Fp.TextPrimary)
                    }
                }
                "done" -> {
                    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
                        Box(Modifier.size(48.dp).clip(CircleShape).background(Fp.GreenLight), contentAlignment = Alignment.Center) {
                            Icon(Icons.Filled.Check, contentDescription = null, tint = Fp.Green, modifier = Modifier.size(28.dp))
                        }
                        Spacer(Modifier.height(10.dp))
                        Text("Import Complete", fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = Fp.TextPrimary)
                        Spacer(Modifier.height(6.dp))
                        Row {
                            Text(imported.toString(), fontSize = 20.sp, color = Fp.Green, fontWeight = FontWeight.Bold, fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace)
                            Text(" imported", fontSize = 13.sp, color = Fp.TextSecondary)
                            if (errors.isNotEmpty()) {
                                Text("   ${errors.size} failed", fontSize = 13.sp, color = Fp.Orange)
                            }
                        }
                        if (errors.isNotEmpty()) {
                            Spacer(Modifier.height(10.dp))
                            Column {
                                errors.take(10).forEach { (file, msg) ->
                                    Text("$file — $msg", fontSize = 10.sp, color = Fp.Orange, fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace, maxLines = 1)
                                }
                                if (errors.size > 10) {
                                    Text("+ ${errors.size - 10} more errors", fontSize = 10.sp, color = Fp.Orange, fontStyle = androidx.compose.ui.text.font.FontStyle.Italic)
                                }
                            }
                        }
                        Spacer(Modifier.height(18.dp))
                        PrimaryButton("View Library") { onComplete() }
                    }
                }
                "error" -> {
                    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
                        Box(Modifier.size(48.dp).clip(CircleShape).background(Fp.RedLight), contentAlignment = Alignment.Center) {
                            Icon(Icons.Filled.ErrorOutline, contentDescription = null, tint = Fp.Red, modifier = Modifier.size(28.dp))
                        }
                        Spacer(Modifier.height(10.dp))
                        Text(
                            if (files.isEmpty() && errors.size == 1) "No Audio Files Found" else "Import Failed",
                            fontSize = 16.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = Fp.TextPrimary,
                        )
                        Spacer(Modifier.height(10.dp))
                        errors.take(10).forEach { (file, msg) ->
                            Text("$file — $msg", fontSize = 10.sp, color = Fp.Red, fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace, maxLines = 1)
                        }
                        Spacer(Modifier.height(18.dp))
                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            SecondaryButton("Close") { onClose() }
                            PrimaryButton("Try Again") {
                                files = emptyList()
                                errors = emptyList()
                                step = "select-source"
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun SummaryRow(label: String, value: String) {
    Row(Modifier.fillMaxWidth().padding(vertical = 2.dp)) {
        Text(label, fontSize = 11.sp, color = Fp.TextSecondary)
        Spacer(Modifier.weight(1f))
        Text(value, fontSize = 11.sp, color = Fp.TextPrimary, fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace, maxLines = 1)
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
