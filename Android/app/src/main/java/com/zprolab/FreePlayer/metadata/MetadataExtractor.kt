package com.zprolab.FreePlayer.metadata

import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.charset.Charset

data class ExtractedMetadata(
    val title: String?,
    val artist: String?,
    val album: String?,
    val genre: String?,
    val year: Int?,
    val trackNumber: Int?,
    val discNumber: Int?,
    val duration: Double,
    val fileName: String,
    val fileSize: Long,
    val fileFormat: String?,
    val bitrate: Int?,
    val sampleRate: Int?,
    val channels: Int?,
    val artwork: ByteArray?,
)

object MetadataExtractor {

    val SUPPORTED_EXTENSIONS = setOf("mp3", "flac", "m4a", "aac", "ogg", "wav", "opus", "mp4")

    fun isAudioFile(path: String): Boolean {
        val ext = path.substringAfterLast('.', "").lowercase()
        return ext in SUPPORTED_EXTENSIONS
    }

    /**
     * Strip downloader suffixes: "Artist - Title_EM.flac" -> "Artist - Title".
     * Mirrors cleanStem in metadata.mm (regex: _[A-Za-z]{1,4}$).
     */
    fun cleanStem(stem: String): String {
        return Regex("_[A-Za-z]{1,4}$").replace(stem, "")
    }

    /**
     * Try to find a sidecar .lrc for an audio file (same dir, same stem,
     * tolerant of _EM/_L downloader suffixes and prefix-style names).
     */
    fun findSidecarLrc(audioPath: String): String? {
        val audioFile = File(audioPath)
        val dir = audioFile.parentFile ?: return null
        val audioStem = cleanStem(audioFile.nameWithoutExtension)
        val lrcs = dir.listFiles { f -> f.extension.lowercase() == "lrc" } ?: return null
        val candidates = mutableListOf<Pair<String, String>>()
        for (name in lrcs) {
            val stem = cleanStem(name.nameWithoutExtension)
            if (stem == audioStem) return name.absolutePath // exact match wins
            candidates.add(stem to name.name)
        }
        // Prefix match: "Welcome Home" is a prefix of "Welcome Home, Son (Remaster)"
        val a = audioStem.lowercase()
        for ((stem, name) in candidates) {
            val s = stem.lowercase()
            val minLen = minOf(a.length, s.length)
            if (minLen >= 8 && s.startsWith(a)) {
                return File(dir, name).absolutePath
            }
        }
        return null
    }

    // ── FLAC VORBIS_COMMENT (manual parse; MediaMetadataRetriever hides these) ──

    private fun parseFlacVorbisComments(path: String): Map<String, String>? {
        val data = try { ByteBuffer.wrap(File(path).readBytes()) } catch (e: Exception) { return null }
        if (data.remaining() < 4 || data.get() != 'f'.code.toByte() ||
            data.get() != 'L'.code.toByte() || data.get() != 'a'.code.toByte() || data.get() != 'C'.code.toByte()
        ) return null

        val tags = HashMap<String, String>()
        while (data.remaining() >= 4) {
            val blockHeader = data.get()
            val type = blockHeader.toInt() and 0x7f
            val len = ((data.get().toInt() and 0xFF) shl 16) or
                ((data.get().toInt() and 0xFF) shl 8) or
                (data.get().toInt() and 0xFF)
            if (data.remaining() < len) return null

            if (type == 4) { // VORBIS_COMMENT
                data.order(ByteOrder.LITTLE_ENDIAN)
                if (data.remaining() < 4) return null
                val vendorLen = data.int
                if (data.remaining() < vendorLen) return null
                data.position(data.position() + vendorLen)
                if (data.remaining() < 4) return null
                val count = data.int
                for (i in 0 until count) {
                    if (data.remaining() < 4) break
                    val clen = data.int
                    if (data.remaining() < clen) break
                    val entry = String(data.array(), data.arrayOffset() + data.position(), clen, Charsets.UTF_8)
                    data.position(data.position() + clen)
                    val eq = entry.indexOf('=')
                    if (eq != -1) {
                        val key = entry.substring(0, eq).lowercase()
                        val value = entry.substring(eq + 1)
                        if (key.isNotEmpty() && value.isNotEmpty()) tags[key] = value
                    }
                }
                return if (tags.isNotEmpty()) tags else null
            }
            data.position(data.position() + len)
        }
        return null
    }

    // ── ID3v2 (v2.3/v2.4) text frames — handles GBK/CJK tags ──

    private fun decodeId3Text(p: ByteArray, start: Int, len: Int): String {
        if (len == 0) return ""
        val enc = p[start].toInt() and 0xFF
        val textStart = start + 1
        var textLen = len - 1
        if (textLen <= 0) return ""
        return when (enc) {
            0 -> { // ISO-8859-1 (often actually GBK for CJK tags)
                var high = 0
                for (i in 0 until textLen) if ((p[textStart + i].toInt() and 0xFF) > 0x7F) high++
                if (textLen > 0 && high * 10 > textLen * 3) {
                    // Mostly high bytes -> likely GBK mislabeled as Latin-1
                    val gb = decodeCjk(p, textStart, textLen, "GBK")
                    if (gb.isNotEmpty() && !gb.contains('\uFFFD')) return gb
                }
                String(p, textStart, textLen, Charsets.ISO_8859_1)
            }
            1 -> { // UTF-16 w/ BOM
                if (textLen >= 2 && p[textStart + textLen - 1].toInt() == 0 && p[textStart + textLen - 2].toInt() == 0) textLen -= 2
                runCatching { String(p, textStart, textLen, Charsets.UTF_16) }.getOrDefault("")
            }
            2 -> runCatching { String(p, textStart, textLen, Charsets.UTF_16BE) }.getOrDefault("")
            else -> String(p, textStart, textLen, Charsets.UTF_8)
        }
    }

    private fun decodeCjk(p: ByteArray, start: Int, len: Int, charset: String): String {
        return runCatching { String(p, start, len, Charset.forName(charset)) }.getOrDefault("")
    }

    private fun parseId3v2(path: String): Map<String, String>? {
        val data = try { File(path).readBytes() } catch (e: Exception) { return null }
        if (data.size < 10 ||
            data[0] != 'I'.code.toByte() || data[1] != 'D'.code.toByte() || data[2] != '3'.code.toByte()
        ) return null
        val ver = data[3].toInt() and 0xFF
        if (ver != 3 && ver != 4) return null
        var tagSize = ((data[6].toInt() and 0x7F) shl 21) or ((data[7].toInt() and 0x7F) shl 14) or
            ((data[8].toInt() and 0x7F) shl 7) or (data[9].toInt() and 0x7F)
        if (tagSize > data.size - 10) tagSize = data.size - 10
        var pos = 10
        val end = 10 + tagSize
        if (pos < end && (data[5].toInt() and 0x40) != 0) { // extended header
            val extSize = if (ver == 4) {
                ((data[pos + 6].toInt() and 0x7F) shl 21) or ((data[pos + 7].toInt() and 0x7F) shl 14) or
                    ((data[pos + 8].toInt() and 0x7F) shl 7) or (data[pos + 9].toInt() and 0x7F)
            } else {
                ((data[pos + 6].toInt() and 0xFF) shl 24) or ((data[pos + 7].toInt() and 0xFF) shl 16) or
                    ((data[pos + 8].toInt() and 0xFF) shl 8) or (data[pos + 9].toInt() and 0xFF)
            }
            pos += 10 + extSize
        }
        val tags = HashMap<String, String>()
        while (pos + 10 <= end) {
            val id = String(data, pos, 4, Charsets.US_ASCII)
            val size = if (ver == 4) {
                ((data[pos + 4].toInt() and 0x7F) shl 21) or ((data[pos + 5].toInt() and 0x7F) shl 14) or
                    ((data[pos + 6].toInt() and 0x7F) shl 7) or (data[pos + 7].toInt() and 0x7F)
            } else {
                ((data[pos + 4].toInt() and 0xFF) shl 24) or ((data[pos + 5].toInt() and 0xFF) shl 16) or
                    ((data[pos + 6].toInt() and 0xFF) shl 8) or (data[pos + 7].toInt() and 0xFF)
            }
            val frameStart = pos + 10
            if (frameStart + size > end) break
            if (size > 0 && id.startsWith("T")) {
                val value = decodeId3Text(data, frameStart, size)
                when (id) {
                    "TIT2" -> tags["title"] = value
                    "TPE1" -> tags["artist"] = value
                    "TALB" -> tags["album"] = value
                    "TYER", "TDRC" -> tags["year"] = value
                    "TCON" -> tags["genre"] = value
                    "TRCK" -> tags["track"] = value
                    "TPOS" -> tags["disc"] = value
                }
            }
            pos = frameStart + size
        }
        return if (tags.isNotEmpty()) tags else null
    }

    // ── main extraction ──

    /**
     * Extract everything the import pipeline needs. Returns null on failure.
     * Call on a background thread.
     */
    fun extractAtPath(path: String): ExtractedMetadata? {
        val file = File(path)
        if (!file.isFile) return null
        val ext = file.extension.lowercase()

        // Stream info via MediaExtractor (sample rate / channels / duration)
        var duration = 0.0
        var sampleRate = 0
        var channels = 0
        try {
            val extractor = MediaExtractor()
            extractor.setDataSource(path)
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                if (format.getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true) {
                    duration = if (format.containsKey(MediaFormat.KEY_DURATION)) {
                        format.getLong(MediaFormat.KEY_DURATION) / 1_000_000.0
                    } else 0.0
                    if (format.containsKey(MediaFormat.KEY_SAMPLE_RATE)) {
                        sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    }
                    if (format.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) {
                        channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    }
                    break
                }
            }
            extractor.release()
        } catch (e: Exception) {
            // fall through; tags may still be readable
        }

        // Tags + artwork via MediaMetadataRetriever
        val mmr = MediaMetadataRetriever()
        try {
            mmr.setDataSource(path)
        } catch (e: Exception) {
            mmr.release()
            return null
        }
        fun mmrText(key: Int): String? {
            return runCatching { mmr.extractMetadata(key) }
                .getOrNull()?.trim()?.ifEmpty { null }
        }
        val mmrTitle = mmrText(MediaMetadataRetriever.METADATA_KEY_TITLE)
        val mmrArtist = mmrText(MediaMetadataRetriever.METADATA_KEY_ARTIST)
        val mmrAlbum = mmrText(MediaMetadataRetriever.METADATA_KEY_ALBUM)
        val mmrGenre = mmrText(MediaMetadataRetriever.METADATA_KEY_GENRE)
        val mmrYearStr = mmrText(MediaMetadataRetriever.METADATA_KEY_DATE)
        val mmrTrackStr = mmrText(MediaMetadataRetriever.METADATA_KEY_CD_TRACK_NUMBER)
        val mmrDiscStr = mmrText(MediaMetadataRetriever.METADATA_KEY_DISC_NUMBER)
        val mmrDurationMs = mmrText(MediaMetadataRetriever.METADATA_KEY_DURATION)
        val artwork = runCatching { mmr.embeddedPicture }.getOrNull()
        mmr.release()

        if (duration <= 0 && mmrDurationMs != null) {
            duration = runCatching { mmrDurationMs.toDouble() / 1000.0 }.getOrDefault(0.0)
        }

        // Manual tag blocks take precedence (deterministic CJK decoding)
        var title: String? = mmrTitle
        var artist: String? = mmrArtist
        var album: String? = mmrAlbum
        var genre: String? = mmrGenre
        var yearStr: String? = mmrYearStr
        var trackNo = 0
        var discNo = 0

        if (ext == "flac") {
            val vorbis = parseFlacVorbisComments(path)
            if (vorbis != null) {
                if (vorbis["title"] != null) title = vorbis["title"]
                if (vorbis["artist"] != null) artist = vorbis["artist"]
                if (vorbis["album"] != null) album = vorbis["album"]
                if (vorbis["genre"] != null) genre = vorbis["genre"]
                if (vorbis["date"] != null) yearStr = vorbis["date"]
                vorbis["tracknumber"]?.let {
                    val slash = it.indexOf('/')
                    trackNo = it.substring(0, if (slash != -1) slash else it.length).trim().toIntOrNull() ?: 0
                }
                vorbis["discnumber"]?.let {
                    val slash = it.indexOf('/')
                    discNo = it.substring(0, if (slash != -1) slash else it.length).trim().toIntOrNull() ?: 0
                }
            }
        } else if (ext == "mp3") {
            val id3 = parseId3v2(path)
            if (id3 != null) {
                if (id3["title"] != null) title = id3["title"]
                if (id3["artist"] != null) artist = id3["artist"]
                if (id3["album"] != null) album = id3["album"]
                if (id3["genre"] != null) genre = id3["genre"]
                if (id3["year"] != null) yearStr = id3["year"]
                if (id3["track"] != null) trackNo = id3["track"]!!.trim().toIntOrNull() ?: 0
                if (id3["disc"] != null) discNo = id3["disc"]!!.trim().toIntOrNull() ?: 0
            }
        }

        if (title == null || title.isEmpty()) {
            title = cleanStem(file.nameWithoutExtension)
        }

        var year: Int? = null
        if (!yearStr.isNullOrEmpty() && yearStr.length >= 4) {
            year = yearStr.substring(0, 4).toIntOrNull()
        }
        if (trackNo == 0 && mmrTrackStr != null) {
            trackNo = mmrTrackStr.substringBefore('/').trim().toIntOrNull() ?: 0
        }
        if (discNo == 0 && mmrDiscStr != null) {
            discNo = mmrDiscStr.substringBefore('/').trim().toIntOrNull() ?: 0
        }

        if (!duration.isFinite() || duration <= 0) duration = 0.0

        val fileSize = file.length()
        // Bitrate from size/duration (kbps), like "1411 kbps"
        var bitrate: Int? = null
        if (duration > 1 && fileSize > 0) {
            bitrate = (fileSize * 8.0 / duration / 1000.0).toInt()
        }

        return ExtractedMetadata(
            title = title,
            artist = if (!artist.isNullOrEmpty()) artist else "Unknown Artist",
            album = if (!album.isNullOrEmpty()) album else "Unknown Album",
            genre = if (!genre.isNullOrEmpty()) genre else null,
            year = year,
            trackNumber = if (trackNo > 0) trackNo else null,
            discNumber = if (discNo > 0) discNo else null,
            duration = duration,
            fileName = file.name,
            fileSize = fileSize,
            fileFormat = ext,
            bitrate = bitrate,
            sampleRate = if (sampleRate > 0) sampleRate else null,
            channels = if (channels > 0) channels else null,
            artwork = artwork,
        )
    }
}
