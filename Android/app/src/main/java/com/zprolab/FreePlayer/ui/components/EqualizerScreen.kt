package com.zprolab.FreePlayer.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.zprolab.FreePlayer.audio.EqualizerEngine
import com.zprolab.FreePlayer.ui.theme.Fp
import kotlin.math.roundToInt

/** Ten logical bands backed by Android's device-specific Equalizer bands. */
@Composable
fun EqualizerScreen(onClose: () -> Unit) {
    val presets = EqualizerEngine.PRESETS
    val frequencies = remember { EqualizerEngine.bandFrequencies() }
    var eqEnabled by remember { mutableStateOf(EqualizerEngine.enabled) }
    var eqPreset by remember { mutableStateOf(EqualizerEngine.preset) }
    var eqGains by remember { mutableStateOf(EqualizerEngine.gains.copyOf()) }

    fun updateBand(index: Int, gain: Float) {
        val updated = eqGains.copyOf()
        updated[index] = ((gain * 2).roundToInt() / 2f).coerceIn(-12f, 12f)
        eqGains = updated
        eqPreset = "Custom"
        EqualizerEngine.setGains(updated)
    }

    Column(
        Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 18.dp, vertical = 16.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column {
                Text("Equalizer", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = Fp.TextPrimary)
                Text(
                    if (eqEnabled) "Active · $eqPreset" else "Disabled",
                    fontSize = 12.sp,
                    color = if (eqEnabled) Fp.Orange else Fp.TextTertiary,
                )
            }
            Spacer(Modifier.weight(1f))
            Text("Enable", fontSize = 13.sp, color = Fp.TextPrimary)
            Spacer(Modifier.width(8.dp))
            Switch(
                checked = eqEnabled,
                onCheckedChange = {
                    eqEnabled = it
                    EqualizerEngine.setEnabled(it)
                },
            )
        }

        Spacer(Modifier.height(18.dp))

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .horizontalScroll(rememberScrollState())
                .alpha(if (eqEnabled) 1f else 0.48f),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            frequencies.forEachIndexed { index, frequency ->
                BandFader(
                    frequency = frequency,
                    gain = eqGains.getOrElse(index) { 0f },
                    enabled = eqEnabled,
                    onGainChange = { updateBand(index, it) },
                )
            }
        }

        Spacer(Modifier.height(18.dp))
        Box(Modifier.fillMaxWidth().height(1.dp).background(Fp.BorderLight))
        Spacer(Modifier.height(14.dp))

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(7.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("Presets", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Fp.TextSecondary)
            presets.forEach { (name, gains) ->
                PresetChip(name, selected = eqPreset == name) {
                    eqPreset = name
                    eqGains = gains.copyOf()
                    EqualizerEngine.setPreset(name)
                }
            }
            PresetChip("Reset", selected = false) {
                val flat = FloatArray(frequencies.size)
                eqPreset = "Flat"
                eqGains = flat
                EqualizerEngine.setGains(flat)
            }
        }
    }
}

@Composable
private fun BandFader(
    frequency: Int,
    gain: Float,
    enabled: Boolean,
    onGainChange: (Float) -> Unit,
) {
    Column(
        modifier = Modifier.width(52.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            String.format("%+.1f", gain),
            fontSize = 10.sp,
            color = if (enabled) Fp.Orange else Fp.TextTertiary,
            fontFamily = FontFamily.Monospace,
        )
        Spacer(Modifier.height(7.dp))
        Box(
            modifier = Modifier
                .width(40.dp)
                .height(150.dp)
                .pointerInput(enabled) {
                    if (!enabled) return@pointerInput
                    fun update(y: Float) {
                        val fraction = 1f - (y / size.height.toFloat()).coerceIn(0f, 1f)
                        onGainChange(-12f + fraction * 24f)
                    }
                    detectDragGestures(
                        onDragStart = { update(it.y) },
                        onDrag = { change, _ ->
                            change.consume()
                            update(change.position.y)
                        },
                    )
                },
            contentAlignment = Alignment.TopCenter,
        ) {
            Box(
                Modifier
                    .width(5.dp)
                    .height(150.dp)
                    .clip(RoundedCornerShape(3.dp))
                    .background(Fp.Border),
            )
            val fraction = ((12f - gain) / 24f).coerceIn(0f, 1f)
            Box(
                Modifier
                    .padding(top = (fraction * 126f).dp)
                    .size(width = 30.dp, height = 24.dp)
                    .clip(RoundedCornerShape(7.dp))
                    .background(if (enabled) Fp.Orange else Fp.Border)
                    .border(1.dp, Color.White.copy(alpha = 0.7f), RoundedCornerShape(7.dp)),
            )
        }
        Spacer(Modifier.height(5.dp))
        Text(
            formatFreq(frequency),
            fontSize = 11.sp,
            color = Fp.TextSecondary,
            fontFamily = FontFamily.Monospace,
        )
    }
}

@Composable
private fun PresetChip(name: String, selected: Boolean, onClick: () -> Unit) {
    Box(
        Modifier
            .clip(RoundedCornerShape(16.dp))
            .background(if (selected) Fp.OrangeLight else Fp.ContentBg)
            .border(1.dp, if (selected) Fp.Orange else Fp.BorderLight, RoundedCornerShape(16.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 13.dp, vertical = 7.dp),
    ) {
        Text(
            name,
            fontSize = 11.sp,
            color = if (selected) Fp.Orange else Fp.TextSecondary,
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
        )
    }
}

private fun formatFreq(hz: Int): String = when {
    hz >= 1000 -> "${hz / 1000}K"
    else -> hz.toString()
}
