package com.zprolab.FreePlayer.metadata

import com.zprolab.FreePlayer.data.Track
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.nio.charset.StandardCharsets

/**
 * Online metadata fetching — Kotlin port of the Swift MetadataFetchService.
 * LRCLIB for synced lyrics, iTunes Search API for cover art. All endpoints
 * are free and require no API key. Requests are paced (1.2s lyrics /
 * 3s cover) because both public endpoints throttle burst traffic.
 */
object OnlineMetadataService {

    data class Candidate(val title: String, val artist: String)

    private var lastLrcRequest = 0L
    private var lastCoverRequest = 0L
    private var lrcCooldownUntil = 0L
    private var coverCooldownUntil = 0L

    private enum class RequestKind { LYRICS, COVER }

    suspend fun fetchLyrics(track: Track): String? = withContext(Dispatchers.IO) {
        if (System.currentTimeMillis() < lrcCooldownUntil) return@withContext null
        val artistKnown = track.artist.isNotEmpty() && track.artist != Track.UNKNOWN_ARTIST

        if (artistKnown) {
            val url = lrclibGetUrl(track)
            if (url != null) {
                paceLrc()
                val data = jsonData(url, RequestKind.LYRICS) ?: return@withContext null
                runCatching {
                    val obj = JSONObject(String(data, StandardCharsets.UTF_8))
                    val lyrics = obj.optString("syncedLyrics")
                    if (lyrics.isNotEmpty() && lyrics != "null") return@withContext lyrics
                    val plain = obj.optString("plainLyrics")
                    if (plain.isNotEmpty() && plain != "null") return@withContext plain
                }
            }
        }

        val searchUrl = lrclibSearchUrl(track) ?: return@withContext null
        paceLrc()
        val data = jsonData(searchUrl, RequestKind.LYRICS) ?: return@withContext null
        runCatching {
            val arr = JSONArray(String(data, StandardCharsets.UTF_8))
            val candidates = mutableListOf<Candidate>()
            val items = mutableListOf<JSONObject>()
            for (i in 0 until arr.length()) {
                val item = arr.getJSONObject(i)
                items.add(item)
                candidates.add(Candidate(item.optString("trackName").ifEmpty { item.optString("track_name") }, item.optString("artistName").ifEmpty { item.optString("artist_name") }))
            }
            val index = bestMatchIndex(candidates, track) ?: return@runCatching null
            val lyrics = items[index].optString("syncedLyrics")
            if (lyrics.isNotEmpty() && lyrics != "null") return@withContext lyrics
            val plain = items[index].optString("plainLyrics")
            if (plain.isNotEmpty() && plain != "null") return@withContext plain
        }
        null
    }

    suspend fun fetchCover(track: Track): ByteArray? = withContext(Dispatchers.IO) {
        if (System.currentTimeMillis() < coverCooldownUntil) return@withContext null
        val url = itunesSearchUrl(track) ?: return@withContext null
        paceCover()
        var data = jsonData(url, RequestKind.COVER)
        if (data == null) {
            delay(500)
            data = jsonData(url, RequestKind.COVER)
        }
        data ?: return@withContext null
        runCatching {
            val obj = JSONObject(String(data, StandardCharsets.UTF_8))
            val results = obj.getJSONArray("results")
            val candidates = mutableListOf<Candidate>()
            val artworks = mutableListOf<String>()
            for (i in 0 until results.length()) {
                val item = results.getJSONObject(i)
                candidates.add(Candidate(item.optString("trackName"), item.optString("artistName")))
                artworks.add(item.optString("artworkUrl100"))
            }
            val index = bestMatchIndex(candidates, track) ?: return@runCatching null
            val artworkUrl = artworks[index]
            val large = largeArtworkUrl(artworkUrl)
            return@withContext binaryData(large)
        }
        null
    }

    // ── matching (port of Swift normalize/similarity/bestMatch) ──

    fun normalizeForMatch(value: String): String =
        value.lowercase()
            .map { if (it.isLetterOrDigit()) it else ' ' }
            .joinToString("")
            .split(Regex("\\s+"))
            .filter { it.isNotEmpty() }
            .joinToString(" ")

    fun similarity(lhs: String, rhs: String): Double {
        val a = normalizeForMatch(lhs)
        val b = normalizeForMatch(rhs)
        if (a.isEmpty() || b.isEmpty()) return 0.0
        if (a == b) return 1.0
        if (a.contains(b) || b.contains(a)) return 0.9
        val left = a.split(" ")
        val right = b.split(" ")
        val common = left.count { right.contains(it) }
        return common.toDouble() / maxOf(left.size, right.size)
    }

    fun bestMatchIndex(candidates: List<Candidate>, track: Track): Int? {
        val unknownArtist = track.artist.isEmpty() || track.artist == Track.UNKNOWN_ARTIST
        var bestIndex: Int? = null
        var bestScore = 0.0
        candidates.forEachIndexed { index, candidate ->
            val titleScore = similarity(candidate.title, track.title)
            if (titleScore < 0.8) return@forEachIndexed
            val artistScore = if (unknownArtist) 1.0 else similarity(candidate.artist, track.artist)
            if (!unknownArtist && artistScore < 0.5) return@forEachIndexed
            val score = titleScore * 0.7 + artistScore * 0.3
            if (score > bestScore) {
                bestScore = score
                bestIndex = index
            }
        }
        return bestIndex
    }

    // ── URL builders ──

    private fun lrclibGetUrl(track: Track): URL? {
        val params = mutableListOf<String>()
        if (track.artist.isNotEmpty() && track.artist != Track.UNKNOWN_ARTIST) {
            params.add("artist_name=${encode(track.artist)}")
        }
        if (track.title.isNotEmpty()) params.add("track_name=${encode(track.title)}")
        if (track.album.isNotEmpty() && track.album != Track.UNKNOWN_ALBUM) {
            params.add("album_name=${encode(track.album)}")
        }
        if (track.duration > 0) params.add("duration=${track.duration.toLong()}")
        return runCatching { URL("https://lrclib.net/api/get?${params.joinToString("&")}") }.getOrNull()
    }

    private fun lrclibSearchUrl(track: Track): URL? {
        val query = listOf(track.title, if (track.artist == Track.UNKNOWN_ARTIST) "" else track.artist)
            .filter { it.isNotEmpty() }.joinToString(" ")
        return runCatching { URL("https://lrclib.net/api/search?q=${encode(query)}") }.getOrNull()
    }

    private fun itunesSearchUrl(track: Track): URL? {
        val term = listOf(track.title, if (track.artist == Track.UNKNOWN_ARTIST) "" else track.artist)
            .filter { it.isNotEmpty() }.joinToString(" ")
        return runCatching {
            URL("https://itunes.apple.com/search?term=${encode(term)}&media=music&entity=song&limit=10")
        }.getOrNull()
    }

    private fun largeArtworkUrl(value: String): String =
        value.replace(Regex("\\d+x\\d+"), "600x600")

    // ── pacing / HTTP ──

    private fun paceLrc() {
        val wait = 1200L - (System.currentTimeMillis() - lastLrcRequest)
        if (wait > 0) Thread.sleep(wait)
        lastLrcRequest = System.currentTimeMillis()
    }

    private fun paceCover() {
        val wait = 3000L - (System.currentTimeMillis() - lastCoverRequest)
        if (wait > 0) Thread.sleep(wait)
        lastCoverRequest = System.currentTimeMillis()
    }

    private fun jsonData(url: URL, kind: RequestKind): ByteArray? {
        try {
            val conn = url.openConnection() as HttpURLConnection
            conn.connectTimeout = 8000
            conn.readTimeout = 8000
            conn.requestMethod = "GET"
            if (conn.responseCode == 429) {
                val cooldown = System.currentTimeMillis() + 30_000
                if (kind == RequestKind.LYRICS) lrcCooldownUntil = cooldown else coverCooldownUntil = cooldown
                return null
            }
            if (conn.responseCode != 200) return null
            return conn.inputStream.use { it.readBytes() }
        } catch (e: Exception) {
            return null
        }
    }

    private fun binaryData(url: String): ByteArray? {
        return runCatching {
            val conn = URL(url).openConnection() as HttpURLConnection
            conn.connectTimeout = 8000
            conn.readTimeout = 8000
            if (conn.responseCode == 429) {
                coverCooldownUntil = System.currentTimeMillis() + 30_000
                return null
            }
            if (conn.responseCode != 200) return null
            conn.inputStream.use { it.readBytes() }
        }.getOrNull()
    }

    private fun encode(value: String): String =
        URLEncoder.encode(value, "UTF-8").replace("+", "%20")
}
