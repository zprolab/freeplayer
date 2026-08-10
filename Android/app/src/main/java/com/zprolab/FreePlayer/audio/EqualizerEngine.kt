package com.zprolab.FreePlayer.audio

import android.media.audiofx.Equalizer
import android.util.Log
import com.zprolab.FreePlayer.playback.PlayerController

/**
 * 10-band parametric equalizer via android.media.audiofx.Equalizer
 * (free, system API) bound to the ExoPlayer audio session.
 *
 * Bands: 31 / 62 / 125 / 250 / 500 / 1k / 2k / 4k / 8k / 16k Hz (device
 * dependent center frequencies), range -12..+12 dB. Mirrors the Swift
 * version's AVAudioUnitEQ setup and presets.
 */
object EqualizerEngine {

    private val logicalFrequencies = intArrayOf(31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000)

    val PRESETS = listOf(
        "Flat" to floatArrayOf(0f, 0f, 0f, 0f, 0f, 0f, 0f, 0f, 0f, 0f),
        "Bass Boost" to floatArrayOf(6f, 6f, 5f, 3.5f, 2f, 0f, 0f, 0f, 0f, 0f),
        "Vocal" to floatArrayOf(0f, 0f, 0f, 0f, 0f, 3f, 3f, 3f, 2f, 0f),
        "Classical" to floatArrayOf(3f, 3f, 2f, 0f, 0f, 0f, 0f, 1.5f, 2f, 3f),
        "Rock" to floatArrayOf(5f, 5f, 4f, 2f, 0f, 0f, 1f, 3f, 4.5f, 5f),
        "Pop" to floatArrayOf(0.5f, 1f, 1.5f, 2.5f, 3f, 3f, 2.5f, 1.5f, 1f, 0.5f),
    )

    @Volatile
    var enabled = false
        private set

    @Volatile
    var preset = "Flat"
        private set

    @Volatile
    var gains = FloatArray(10) { 0f }
        private set

    private var equalizer: Equalizer? = null
    private var sessionId = -1
    private var bandCount = 0

    /** Attach to the player's audio session; re-attaches when it changes. */
    fun attach(audioSessionId: Int) {
        if (audioSessionId <= 0) return
        if (sessionId == audioSessionId && equalizer != null) return
        release()
        sessionId = audioSessionId
        try {
            val eq = Equalizer(0, audioSessionId)
            bandCount = minOf(eq.numberOfBands.toInt(), 10)
            equalizer = eq
            apply()
            Log.d("FP_EQ", "attached session $audioSessionId bands=$bandCount")
        } catch (e: Exception) {
            Log.w("FP_EQ", "attach failed: ${e.message}")
            equalizer = null
        }
    }

    /** Stable 10-band labels used by every platform UI. */
    fun bandFrequencies(): List<Int> = logicalFrequencies.toList()

    fun setEnabled(value: Boolean) {
        enabled = value
        apply()
        PlayerController.db.setSetting("eq_enabled", value.toString())
    }

    fun setPreset(name: String) {
        val found = PRESETS.firstOrNull { it.first == name }
        preset = name
        if (found != null) {
            gains = found.second.copyOf()
        }
        apply()
        PlayerController.db.setSetting("eq_preset", name)
        PlayerController.db.setSetting("eq_gains", gains.joinToString(","))
    }

    fun setGains(values: FloatArray) {
        gains = FloatArray(logicalFrequencies.size) { index ->
            values.getOrElse(index) { 0f }.coerceIn(-12f, 12f)
        }
        apply()
        PlayerController.db.setSetting("eq_preset", "Custom")
        PlayerController.db.setSetting("eq_gains", gains.joinToString(","))
        if (preset != "Custom") {
            preset = "Custom"
            PlayerController.db.setSetting("eq_preset", "Custom")
        }
    }

    /** Restore persisted state (called on app start). */
    fun restore() {
        val db = PlayerController.db
        enabled = db.getSetting("eq_enabled", "false")?.toBoolean() ?: false
        preset = db.getSetting("eq_preset", "Flat") ?: "Flat"
        val gainsStr = db.getSetting("eq_gains", null)
        if (gainsStr != null) {
            val parts = gainsStr.split(",").mapNotNull { it.toFloatOrNull() }
            if (parts.size == 10) gains = parts.toFloatArray()
        } else {
            PRESETS.firstOrNull { it.first == preset }?.let { gains = it.second.copyOf() }
        }
        apply()
    }

    fun release() {
        runCatching { equalizer?.enabled = false }
        runCatching { equalizer?.release() }
        equalizer = null
    }

    private fun apply() {
        val eq = equalizer ?: return
        try {
            eq.enabled = enabled
            val levelRange = eq.bandLevelRange
            for (i in 0 until bandCount) {
                // Android devices commonly expose five physical bands. Map each
                // physical center frequency to the nearest logical 10-band gain.
                val hz = eq.getCenterFreq(i.toShort()) / 1000.0
                val logicalIndex = logicalFrequencies.indices.minByOrNull { index ->
                    kotlin.math.abs(kotlin.math.ln(hz.coerceAtLeast(1.0) / logicalFrequencies[index]))
                } ?: i.coerceIn(gains.indices)
                val millibels = (gains[logicalIndex] * 100).toInt()
                    .coerceIn(levelRange[0].toInt(), levelRange[1].toInt())
                eq.setBandLevel(i.toShort(), millibels.toShort())
            }
        } catch (e: Exception) {
            Log.w("FP_EQ", "apply failed: ${e.message}")
        }
    }
}
