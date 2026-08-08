package com.zprolab.FreePlayer.ui.components

import android.graphics.Bitmap
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.ViewAgenda
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.zprolab.FreePlayer.audio.VisualizerEngine
import com.zprolab.FreePlayer.ui.theme.Fp
import kotlinx.coroutines.delay
import kotlin.math.max

const val VIS_MODE_WAVEFORM = "waveform"
const val VIS_MODE_SPECTROGRAM = "spectrogram"
const val VIS_MODE_OFF = "off"

private val SPECTRO_FREQ_LABELS = listOf(20, 100, 500, 2000, 8000, 20000)
private val SPECTRO_FREQ_X = listOf(0.04f, 0.22f, 0.40f, 0.58f, 0.76f, 0.94f)

/**
 * Port of WaveformVisualizer.jsx — three modes on a Canvas:
 * waveform (oscilloscope + spectrum bars), spectrogram (thermal waterfall),
 * off (dashed placeholder).
 */
@Composable
fun WaveformVisualizer(
    engine: VisualizerEngine,
    isPlaying: Boolean,
    trackId: Long?,
    mode: String,
    onModeChange: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val spectroRows = 200
    val spectroBitmap = remember {
        Bitmap.createBitmap(engine.captureSize / 2, spectroRows, Bitmap.Config.ARGB_8888)
    }
    val pixelBuf = remember { IntArray(engine.captureSize / 2 * spectroRows) }
    val spectroReady = remember { java.util.concurrent.atomic.AtomicBoolean(false) }
    val lastFft = remember { ByteArray(engine.captureSize) }
    val smoothing = remember { FloatArray(engine.captureSize / 2) }

    // Frame clock: the visualizer data (waveform/fft) lives in plain fields,
    // which Compose can't observe. This state ticks every vsync while playing
    // so the Canvas onDraw re-runs each frame with fresh data.
    var frame by remember { androidx.compose.runtime.mutableLongStateOf(0L) }
    LaunchedEffect(isPlaying, mode) {
        while (isPlaying && mode != VIS_MODE_OFF) {
            androidx.compose.runtime.withFrameNanos { frame = it }
        }
    }

    LaunchedEffect(trackId, isPlaying, mode) {
        while (true) {
            if (mode == VIS_MODE_OFF || !isPlaying) {
                delay(200)
                continue
            }
            val fft = engine.fft
            if (fft.size >= engine.captureSize) {
                System.arraycopy(fft, 0, lastFft, 0, engine.captureSize)
                val bins = engine.captureSize / 2
                // exponential smoothing (analyser smoothingTimeConstant ≈ 0.65)
                for (i in 0 until bins) {
                    val mag = engine.magnitude(i)
                    smoothing[i] = smoothing[i] * 0.35f + mag * 0.65f
                }
                if (mode == VIS_MODE_SPECTROGRAM) {
                    shiftAndAppendRow(pixelBuf, bins, spectroRows, smoothing, spectroBitmap.width)
                    spectroBitmap.setPixels(pixelBuf, 0, bins, 0, 0, bins, spectroRows)
                    spectroReady.set(true)
                }
            }
            delay(16)
        }
    }

    Box(
        modifier
            .fillMaxWidth()
            .height(320.dp)
            .clip(RoundedCornerShape(6.dp))
            .background(Fp.VisualizerBg)
            .border(1.dp, Fp.BorderDark, RoundedCornerShape(6.dp))
    ) {
        when (mode) {
            VIS_MODE_OFF -> OffPlaceholder { onModeChange(VIS_MODE_WAVEFORM) }
            VIS_MODE_SPECTROGRAM -> SpectroCanvas(spectroBitmap, spectroReady.get(), isPlaying, mode, frame)
            else -> WaveformCanvas(engine, lastFft, smoothing, isPlaying, frame)
        }

        // Control bar (top-right)
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(8.dp)
                .clip(RoundedCornerShape(4.dp))
                .background(Color(0x660d0d10))
                .padding(horizontal = 6.dp, vertical = 4.dp),
            horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(2.dp),
        ) {
            ModeButton(Icons.Filled.GraphicEq, mode == VIS_MODE_WAVEFORM) { onModeChange(VIS_MODE_WAVEFORM) }
            ModeButton(Icons.Filled.ViewAgenda, mode == VIS_MODE_SPECTROGRAM) { onModeChange(VIS_MODE_SPECTROGRAM) }
            ModeButton(Icons.Filled.Close, false, color = Fp.Red) { onModeChange(VIS_MODE_OFF) }
        }
    }
}

@Composable
private fun ModeButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    active: Boolean,
    color: Color = Color.White,
    onClick: () -> Unit,
) {
    Box(
        Modifier
            .size(26.dp)
            .clip(RoundedCornerShape(4.dp))
            .background(if (active) Fp.Orange.copy(alpha = 0.2f) else Color.Transparent)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = null, tint = if (active) Fp.Orange else color, modifier = Modifier.size(16.dp))
    }
}

@Composable
private fun OffPlaceholder(onEnable: () -> Unit) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                "VISUALIZER OFF",
                color = Color(0x73ffffff),
                fontSize = 10.sp,
                fontFamily = FontFamily.Monospace,
                letterSpacing = 0.1f.sp,
            )
            Spacer(Modifier.height(6.dp))
            Box(
                Modifier
                    .clip(RoundedCornerShape(4.dp))
                    .border(1.dp, Fp.Orange, RoundedCornerShape(4.dp))
                    .clickable(onClick = onEnable)
                    .padding(horizontal = 14.dp, vertical = 6.dp),
            ) {
                Text("Enable", color = Fp.Orange, fontSize = 12.sp)
            }
        }
    }
}

@Composable
private fun SpectroCanvas(bitmap: Bitmap, ready: Boolean, isPlaying: Boolean, mode: String, frame: Long) {
    Canvas(Modifier.fillMaxSize()) {
        // draw-phase dependency: redraws every vsync while playing
        @Suppress("UNUSED_EXPRESSION")
        frame
        drawRect(Color(0xFF1a1a1e))
        if (ready) {
            drawImage(
                bitmap.asImageBitmap(),
                dstSize = androidx.compose.ui.unit.IntSize(size.width.toInt(), size.height.toInt()),
            )
        } else if (!isPlaying) {
            drawNoSignal()
        }
        // grid lines + freq labels
        val gridColor = Fp.VisualizerGrid
        for (i in 1..6) {
            val y = size.height * i / 7f
            drawLine(gridColor, Offset(0f, y), Offset(size.width, y), strokeWidth = 1f)
        }
        drawFreqLabels()
        // peak bar
        val peak = maxPeak(smoothingPeak)
        drawRect(
            Fp.Orange.copy(alpha = 0.15f + peak * 0.4f),
            topLeft = Offset(0f, size.height - 1.5f),
            size = androidx.compose.ui.geometry.Size(size.width * peak.coerceAtMost(1f), 1.5f),
        )
        // time direction labels
        drawText("now", 10f, size.height - 24f, Color(0x59ffffff), 7f, left = size.width - 30f)
        drawText("←", 10f, size.height - 24f, Color(0x59ffffff), 7f, left = 6f)
    }
}

private var smoothingPeak = 0f

@Composable
private fun WaveformCanvas(
    engine: VisualizerEngine,
    lastFft: ByteArray,
    smoothing: FloatArray,
    isPlaying: Boolean,
    frame: Long,
) {
    Canvas(Modifier.fillMaxSize()) {
        // draw-phase dependency: redraws every vsync while playing
        @Suppress("UNUSED_EXPRESSION")
        frame
        drawRect(Color(0xFF1a1a1e))
        if (!isPlaying) {
            drawNoSignal()
            return@Canvas
        }
        val wave = engine.waveform
        val wfTop = size.height * 0.08f
        val wfH = size.height * 0.47f
        val sepY = wfTop + wfH
        val specTop = sepY + size.height * 0.02f
        val specH = size.height * 0.38f

        // grid
        val gridColor = Fp.VisualizerGrid
        val gridStrong = Color(0x33108548)
        for (i in 0 until 16) {
            val x = size.width * i / 15f
            drawLine(gridColor, Offset(x, wfTop), Offset(x, specTop + specH), strokeWidth = 1f)
        }
        drawLine(Color(0x33108548), Offset(0f, wfTop + wfH * 0.25f), Offset(size.width, wfTop + wfH * 0.25f), strokeWidth = 1f)
        drawLine(gridStrong, Offset(0f, wfTop + wfH * 0.5f), Offset(size.width, wfTop + wfH * 0.5f), strokeWidth = 1f)
        drawLine(Color(0x33108548), Offset(0f, wfTop + wfH * 0.75f), Offset(size.width, wfTop + wfH * 0.75f), strokeWidth = 1f)
        drawLine(Color(0x33108548), Offset(0f, specTop + specH * 0.25f), Offset(size.width, specTop + specH * 0.25f), strokeWidth = 1f)
        drawLine(Color(0x33108548), Offset(0f, specTop + specH * 0.5f), Offset(size.width, specTop + specH * 0.5f), strokeWidth = 1f)
        drawLine(Color(0x33108548), Offset(0f, specTop + specH * 0.75f), Offset(size.width, specTop + specH * 0.75f), strokeWidth = 1f)
        drawLine(gridStrong, Offset(0f, specTop + specH), Offset(size.width, specTop + specH), strokeWidth = 1f)

        // waveform (3-layer stroke)
        if (wave.isNotEmpty()) {
            val path = androidx.compose.ui.graphics.Path()
            val n = wave.size
            for (i in 0 until n) {
                val x = size.width * i / (n - 1)
                val v = (wave[i].toInt() and 0xFF) / 128f - 1f
                val y = wfTop + wfH * 0.5f + v * wfH * 0.46f
                if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
            }
            drawPath(path, Fp.Orange.copy(alpha = 0.22f), style = androidx.compose.ui.graphics.drawscope.Stroke(width = 5f))
            drawPath(path, Fp.Orange.copy(alpha = 0.38f), style = androidx.compose.ui.graphics.drawscope.Stroke(width = 2f))
            drawPath(path, Fp.Orange.copy(alpha = 0.92f), style = androidx.compose.ui.graphics.drawscope.Stroke(width = 1f))
        }

        // spectrum bars (128 bars over 512 bins)
        var maxFreq = 0f
        for (b in 0 until 128) {
            val startBin = b * 4
            var sum = 0f
            for (k in 0 until 4) sum += smoothing.getOrElse(startBin + k) { 0f }
            val v = sum / 4f
            maxFreq = max(maxFreq, v)
        }
        if (maxFreq > 0.05f) {
            val slot = size.width / 128f
            val barW = (slot * 0.68f).coerceAtLeast(1.5f)
            for (b in 0 until 128) {
                val startBin = b * 4
                var sum = 0f
                for (k in 0 until 4) sum += smoothing.getOrElse(startBin + k) { 0f }
                val v = sum / 4f
                val h = (v * specH).coerceAtLeast(0f)
                val x = b * slot + (slot - barW) / 2f
                drawRect(barColor(v), topLeft = Offset(x, specTop + specH - h), size = androidx.compose.ui.geometry.Size(barW, h))
            }
        }

        // labels
        drawText("L", 10f, wfTop + 4f, Color(0x73ffffff), 10f, left = 8f)
        drawText("R", 10f, wfTop + wfH - 16f, Color(0x73ffffff), 10f, left = 8f)
        drawText("+1", 10f, wfTop + 2f, Color(0x59ffffff), 9f, left = 20f)
        drawText("−1", 10f, wfTop + wfH - 16f, Color(0x59ffffff), 9f, left = 20f)
        drawFreqLabels()
        drawText("Hz", 10f, specTop + specH + 14f, Color(0x59ffffff), 9f, left = size.width - 24f)

        // bottom peak bar
        val peak = maxFreq.coerceAtMost(1f)
        drawRect(
            Fp.Orange.copy(alpha = 0.15f + peak * 0.4f),
            topLeft = Offset(0f, size.height - 1.5f),
            size = androidx.compose.ui.geometry.Size(size.width * peak, 1.5f),
        )
    }
}

private fun DrawScope.drawFreqLabels() {
    for (i in SPECTRO_FREQ_LABELS.indices) {
        val label = when (SPECTRO_FREQ_LABELS[i]) {
            20 -> "20"
            100 -> "100"
            500 -> "500"
            2000 -> "2k"
            8000 -> "8k"
            else -> "20k"
        }
        drawText(label, 10f, size.height - 24f, Color(0x59ffffff), 9f, left = size.width * SPECTRO_FREQ_X[i])
    }
}

private fun DrawScope.drawNoSignal() {
    drawText("NO SIGNAL", 11f, 0f, Color(0x40ffffff), 11f, center = true)
}

private fun DrawScope.drawText(text: String, height: Float, yOffset: Float, color: Color, sp: Float, left: Float = 0f, center: Boolean = false) {
    val paint = android.graphics.Paint().apply {
        this.color = color.toArgb()
        this.textSize = sp * 3f
        this.typeface = android.graphics.Typeface.MONOSPACE
    }
    val x = if (center) (size.width - paint.measureText(text)) / 2f else left
    drawContext.canvas.nativeCanvas.drawText(text, x, height + yOffset, paint)
}

private fun barColor(v: Float): Color {
    // interpolate rgb(45→120, 100→150, 195→230) with v
    val t = v.coerceIn(0f, 1f)
    val r = 45 + (120 - 45) * t
    val g = 100 + (150 - 100) * t
    val b = 195 + (230 - 195) * t
    return Color(r.toInt(), g.toInt(), b.toInt())
}

private fun maxPeak(v: Float): Float = v.coerceIn(0f, 1f)

/** Shift the spectrogram history up one row and append the newest FFT row. */
private fun shiftAndAppendRow(
    pixels: IntArray,
    bins: Int,
    rows: Int,
    row: FloatArray,
    width: Int,
) {
    val rowCount = bins.coerceAtMost(rows)
    if (bins < width) {
        System.arraycopy(pixels, bins, pixels, 0, pixels.size - bins)
    } else {
        System.arraycopy(pixels, width, pixels, 0, (rows - 1) * width)
    }
    var idx = (rows - 1) * width
    for (b in 0 until width) {
        val v = row.getOrElse(b) { 0f }
        pixels[idx++] = thermalColor(v).toArgb()
    }
    smoothingPeak = (0 until width).maxOfOrNull { row.getOrElse(it) { 0f } } ?: 0f
}

private fun thermalColor(v: Float): Color {
    val t = v.coerceIn(0f, 1f)
    return when {
        t <= 0f -> Color(0xFF0F0F14)
        t < 0.2f -> Color(15, 15, 20 + (60 * t / 0.2f).toInt())
        t < 0.4f -> Color((30 * (t - 0.2f) / 0.2f).toInt(), (60 * (t - 0.2f) / 0.2f).toInt(), 120)
        t < 0.55f -> Color(30, 60 + (100 * (t - 0.4f) / 0.15f).toInt(), 120 + (40 * (t - 0.4f) / 0.15f).toInt())
        t < 0.7f -> Color(60 + (150 * (t - 0.55f) / 0.15f).toInt(), 160, 160 - (80 * (t - 0.55f) / 0.15f).toInt())
        t < 0.85f -> Color(210 + (45 * (t - 0.7f) / 0.15f).toInt(), 190 - (80 * (t - 0.7f) / 0.15f).toInt(), 80 - (60 * (t - 0.7f) / 0.15f).toInt())
        else -> Color(255, 110 - (30 * (t - 0.85f) / 0.15f).toInt(), 20 - (15 * (t - 0.85f) / 0.15f).toInt())
    }
}
