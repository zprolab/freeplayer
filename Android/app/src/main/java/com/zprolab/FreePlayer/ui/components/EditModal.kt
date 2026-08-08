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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
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
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import com.zprolab.FreePlayer.data.Track
import com.zprolab.FreePlayer.ui.theme.Fp

/**
 * Port of EditModal.jsx — edit track metadata.
 * Title required; empty artist/album -> "Unknown Artist"/"Unknown Album";
 * empty genre/year -> null.
 */
@Composable
fun EditModal(
    track: Track,
    onClose: () -> Unit,
    onSave: (Long, Map<String, Any?>) -> Unit,
) {
    var title by remember { mutableStateOf(track.title) }
    var artist by remember { mutableStateOf(track.artist) }
    var album by remember { mutableStateOf(track.album) }
    var genre by remember { mutableStateOf(track.genre ?: "") }
    var year by remember { mutableStateOf(track.year?.toString() ?: "") }
    var error by remember { mutableStateOf<String?>(null) }
    var saving by remember { mutableStateOf(false) }

    fun submit() {
        if (saving) return
        if (title.isBlank()) {
            error = "Title cannot be empty"
            return
        }
        saving = true
        val fields = mutableMapOf<String, Any?>(
            "title" to title.trim(),
            "artist" to artist.trim().ifEmpty { "Unknown Artist" },
            "album" to album.trim().ifEmpty { "Unknown Album" },
            "genre" to genre.trim().ifEmpty { null },
            "year" to year.trim().toIntOrNull(),
        )
        onSave(track.id, fields)
        onClose()
    }

    Dialog(onDismissRequest = onClose) {
        Column(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(8.dp))
                .background(Color.White)
                .padding(24.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Edit Track", fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = Fp.TextPrimary)
                Spacer(Modifier.weight(1f))
                Icon(Icons.Filled.Close, contentDescription = "Close", tint = Fp.TextTertiary, modifier = Modifier.size(18.dp).clickable { onClose() })
            }
            Spacer(Modifier.height(16.dp))

            if (error != null) {
                Box(
                    Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(4.dp))
                        .background(Fp.RedLight)
                        .padding(8.dp),
                ) {
                    Text(error!!, fontSize = 11.sp, color = Fp.Red, fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace)
                }
                Spacer(Modifier.height(10.dp))
            }

            Field("Title", title, onChange = { title = it }, onEnter = { submit() })
            Spacer(Modifier.height(10.dp))
            Field("Artist", artist, onChange = { artist = it }, onEnter = { submit() })
            Spacer(Modifier.height(10.dp))
            Field("Album", album, onChange = { album = it }, onEnter = { submit() })
            Spacer(Modifier.height(10.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
                Box(Modifier.weight(1f)) {
                    Field("Genre", genre, onChange = { genre = it }, onEnter = { submit() })
                }
                Box(Modifier.width(100.dp)) {
                    Field("Year", year, onChange = { year = it }, onEnter = { submit() })
                }
            }

            Spacer(Modifier.height(18.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
                Text("↵ to save", fontSize = 11.sp, color = Fp.TextTertiary, fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace, modifier = Modifier.weight(1f).align(Alignment.CenterVertically))
                SecondaryButton("Cancel") { onClose() }
                Box(
                    Modifier
                        .clip(RoundedCornerShape(4.dp))
                        .background(if (saving) Fp.Border else Fp.Orange)
                        .clickable(enabled = !saving, onClick = { submit() })
                        .padding(horizontal = 14.dp, vertical = 7.dp),
                ) {
                    Text(if (saving) "Saving…" else "Save", fontSize = 12.sp, color = Color.White, fontWeight = FontWeight.Medium)
                }
            }
        }
    }
}

@Composable
private fun Field(label: String, value: String, onChange: (String) -> Unit, onEnter: () -> Unit = {}) {
    Column(Modifier.fillMaxWidth()) {
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
            BasicTextField(
                value = value,
                onValueChange = onChange,
                singleLine = true,
                textStyle = TextStyle(fontSize = 13.sp, color = Fp.TextPrimary),
                cursorBrush = SolidColor(Fp.Blue),
                keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(imeAction = androidx.compose.ui.text.input.ImeAction.Done),
                keyboardActions = androidx.compose.foundation.text.KeyboardActions(onDone = { onEnter() }),
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
