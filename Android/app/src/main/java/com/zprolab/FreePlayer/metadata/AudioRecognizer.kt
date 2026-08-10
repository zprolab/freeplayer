package com.zprolab.FreePlayer.metadata

import com.geecko.fpcalc.FpCalc
import com.zprolab.FreePlayer.data.Track
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.nio.charset.StandardCharsets

/**
 * Content-based audio identification — Kotlin port of the Swift
 * AudioRecognizer. Uses Chromaprint (via the vendored fpcalc-android JNI
 * library) for fingerprinting and the AcoustID web service for recognition.
 * All free, no paid API.
 */
object AudioRecognizer {

    const val defaultAPIKey = "j63lxXduqF"

    /** Below this AcoustID score the match is considered unreliable. */
    const val minimumScore = 0.8

    private var apiKeyCache: String? = null

    fun apiKey(): String {
        apiKeyCache?.let { return it }
        val stored = com.zprolab.FreePlayer.playback.PlayerController.db
            .getSetting("acoustid_api_key", null)
        val key = if (stored.isNullOrEmpty()) defaultAPIKey else stored
        apiKeyCache = key
        return key
    }

    fun setApiKey(value: String) {
        val normalized = value.trim()
        com.zprolab.FreePlayer.playback.PlayerController.db.setSetting("acoustid_api_key", normalized)
        apiKeyCache = normalized.ifEmpty { defaultAPIKey }
    }

    data class RecognizedTrack(val title: String, val artist: String, val score: Double)

    /** Chromaprint fingerprint (base64) of an audio file, or null. */
    fun fingerprint(path: String): String? {
        return runCatching {
            val output = FpCalc.fpCalc(arrayOf("-length", "120", path))
            if (output.isNullOrEmpty()) return null
            // fpcalc output: "FINGERPRINT=<base64>\nDURATION=<sec>"
            val line = output.lineSequence().firstOrNull { it.startsWith("FINGERPRINT=") }
                ?: return null
            line.removePrefix("FINGERPRINT=").trim().ifEmpty { null }
        }.getOrNull()
    }

    /**
     * Recognize a local audio file by its content. Returns the best match
     * with its score, or null when unrecognized.
     */
    suspend fun recognize(path: String): RecognizedTrack? = withContext(Dispatchers.IO) {
        val fp = fingerprint(path) ?: return@withContext null
        val duration = audioDuration(path)

        val url = runCatching {
            URL(
                "https://api.acoustid.org/v2/lookup" +
                    "?client=${encode(apiKey())}" +
                    "&fingerprint=${encode(fp)}" +
                    "&duration=$duration&meta=recordings"
            )
        }.getOrNull() ?: run {
            android.util.Log.e("FP_REC", "url build failed")
            return@withContext null
        }
        try {
            val conn = url.openConnection() as HttpURLConnection
            conn.connectTimeout = 8000
            conn.readTimeout = 8000
            if (conn.responseCode != 200) return@withContext null
            val body = conn.inputStream.use { String(it.readBytes(), StandardCharsets.UTF_8) }
            val obj = JSONObject(body)
            val results = obj.optJSONArray("results") ?: return@withContext null
            if (results.length() == 0) return@withContext null
            val first = results.getJSONObject(0)
            val recordings = first.optJSONArray("recordings") ?: return@withContext null
            if (recordings.length() == 0) return@withContext null
            val rec = recordings.getJSONObject(0)
            val title = rec.optString("title").ifEmpty { return@withContext null }
            val artists = rec.optJSONArray("artists")
            val artist = if (artists != null && artists.length() > 0) {
                artists.getJSONObject(0).optString("name")
            } else ""
            RecognizedTrack(title, artist, first.optDouble("score", 0.0))
        } catch (e: Exception) {
            null
        }
    }

    private fun audioDuration(path: String): Long {
        return runCatching {
            val mmr = android.media.MediaMetadataRetriever()
            mmr.setDataSource(path)
            val ms = mmr.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            mmr.release()
            (ms / 1000).coerceAtLeast(1)
        }.getOrDefault(1)
    }

    private fun encode(value: String): String =
        java.net.URLEncoder.encode(value, "UTF-8").replace("+", "%20")
}
