package com.zprolab.FreePlayer.audio

import android.media.audiofx.Visualizer
import android.util.Log
import kotlin.math.max

/**
 * AudioEngine equivalent — taps the playback audio session for
 * waveform + FFT data. Attaches to the ExoPlayer's audio session id.
 *
 * Desktop uses an AnalyserNode with fftSize=2048, smoothing 0.65,
 * -90..-10 dB. Android's Visualizer caps capture at 1024 (512 FFT bins)
 * and samples far slower than 60fps, so the consumer smooths between
 * samples (same visual effect as the analyser's time constant).
 */
class VisualizerEngine {

    private var visualizer: Visualizer? = null
    private var sessionId = -1

    @Volatile
    var waveform: ByteArray = ByteArray(0)
        private set

    @Volatile
    var fft: ByteArray = ByteArray(0)
        private set

    @Volatile
    var attached: Boolean = false
        private set

    val captureSize: Int = 1024

    /** Attach to an audio session; no-op if already attached to it. */
    fun attach(audioSessionId: Int) {
        if (audioSessionId <= 0) return
        if (sessionId == audioSessionId && visualizer != null) return
        release()
        sessionId = audioSessionId
        try {
            val v = Visualizer(audioSessionId)
            v.captureSize = captureSize
            waveform = ByteArray(captureSize)
            fft = ByteArray(captureSize)
            v.setDataCaptureListener(
                object : Visualizer.OnDataCaptureListener {
                    override fun onWaveFormDataCapture(
                        visualizer: Visualizer?,
                        waveformData: ByteArray,
                        samplingRate: Int,
                    ) {
                        waveform = waveformData
                    }

                    override fun onFftDataCapture(
                        visualizer: Visualizer?,
                        fftData: ByteArray,
                        samplingRate: Int,
                    ) {
                        fft = fftData
                    }
                },
                Visualizer.getMaxCaptureRate() / 2,
                true,
                true,
            )
            v.enabled = true
            visualizer = v
            attached = true
        } catch (e: Exception) {
            visualizer = null
            attached = false
            Log.w(TAG, "Unable to attach visualizer to audio session $audioSessionId", e)
        }
    }

    /** Magnitude of FFT bin i (dB range, scaled 0..1 like analyser output). */
    fun magnitude(bin: Int): Float {
        if (bin < 0 || bin >= fft.size / 2) return 0f
        val r = fft[bin * 2].toFloat() / 128.0f
        val i = fft[bin * 2 + 1].toFloat() / 128.0f
        return max(0f, Math.sqrt((r * r + i * i).toDouble()).toFloat().coerceAtMost(1f))
    }

    fun release() {
        runCatching { visualizer?.enabled = false }
        runCatching { visualizer?.release() }
        visualizer = null
        attached = false
    }

    private companion object {
        const val TAG = "FreePlayerVisualizer"
    }
}
