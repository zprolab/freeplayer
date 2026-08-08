package com.zprolab.FreePlayer.util

import java.nio.charset.Charset

data class LrcLine(val time: Double, val text: String)

object LrcParser {

    // Exact port of LyricsDisplay.jsx parseLRC:
    //   /\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]/g
    // minutes 1-3 digits, ':' then exactly-2-digit seconds,
    // optional '.'/':' centiseconds (1-3 digits).
    private val TIME_TAG = Regex("""\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?]""")

    /**
     * Parse raw LRC text into { time, text } entries:
     * - one line may carry multiple time tags (each yields an entry)
     * - lines without time tags (metadata like [ti:...]) are skipped
     * - text is whatever follows the last ']' (sanitized, trimmed)
     * - empty texts skipped, sorted by time,
     *   adjacent entries with identical text deduplicated
     */
    fun parse(content: String): List<LrcLine> {
        val entries = mutableListOf<LrcLine>()
        for (raw in content.lines()) {
            val line = raw.trim()
            if (line.isEmpty()) continue
            val matches = TIME_TAG.findAll(line).toList()
            if (matches.isEmpty()) continue
            val text = sanitizeText(line.substring(line.lastIndexOf(']') + 1).trim())
            if (text.isEmpty()) continue
            for (m in matches) {
                val minutes = m.groupValues[1].toIntOrNull() ?: continue
                val seconds = m.groupValues[2].toIntOrNull() ?: continue
                val csStr = m.groupValues[3]
                val centiseconds = if (csStr.isNotEmpty()) {
                    csStr.padEnd(2, '0').take(2).toIntOrNull() ?: 0
                } else 0
                val time = minutes * 60.0 + seconds + centiseconds / 100.0
                entries.add(LrcLine(time, text))
            }
        }
        val sorted = entries.sortedBy { it.time }
        val deduped = mutableListOf<LrcLine>()
        for (l in sorted) {
            if (deduped.isEmpty() || deduped.last().text != l.text) deduped.add(l)
        }
        return deduped
    }

    /**
     * Decode LRC bytes with the desktop encoding chain
     * (UTF-8 -> GB18030 -> Shift_JIS; README also lists Big5/EUC-KR).
     *
     * GB18030 will happily "decode" Shift_JIS bytes into valid-looking
     * garbage (no replacement char), so when both GB18030 and Shift_JIS
     * decode cleanly we prefer Shift_JIS unless the GB18030 result is
     * clearly Chinese — detected by the Shift_JIS result containing
     * half-width katakana (a strong sign of a misdecoded GBK/GB18030 file).
     */
    fun decodeLrc(raw: ByteArray): String {
        val utf8 = tryDecode(raw, Charsets.UTF_8)
        if (utf8 != null && utf8.length > 0) return sanitizeText(utf8)

        val gb = tryDecode(raw, Charset.forName("GB18030"))
            ?: tryDecode(raw, Charset.forName("GBK"))
        val sjis = tryDecode(raw, Charset.forName("Shift_JIS"))

        if (sjis != null) {
            val sjisHalfWidthKana = sjis.any { it.code in 0xFF61..0xFF9F }
            if (gb == null || !sjisHalfWidthKana) {
                return sanitizeText(sjis)
            }
        }
        if (gb != null) return sanitizeText(gb)

        for (charset in listOf("Big5", "EUC-KR")) {
            val d = tryDecode(raw, Charset.forName(charset))
            if (d != null) return sanitizeText(d)
        }
        return sanitizeText(raw.toString(Charsets.UTF_8))
    }

    private fun tryDecode(raw: ByteArray, charset: Charset): String? {
        return runCatching { String(raw, charset) }
            .getOrNull()
            ?.takeIf { !it.contains('\uFFFD') }
    }

    /**
     * Sanitize lyric text: replace control chars and non-renderable
     * glyphs with spaces (port of sanitizeText).
     */
    fun sanitizeText(text: String): String {
        val sb = StringBuilder(text.length)
        for (ch in text) {
            val code = ch.code
            val replace = when {
                code in 0x00..0x1F && code != '\t'.code && code != '\n'.code && code != '\r'.code -> true
                code in 0x7F..0x9F -> true
                code in 0x200B..0x200F -> true
                code in 0x2028..0x202E -> true
                code in 0x2060..0x206F -> true
                code == 0xFEFF -> true
                code == 0xFFFD -> true
                else -> false
            }
            sb.append(if (replace) ' ' else ch)
        }
        return sb.toString()
    }

    /** Active line index: last line with time <= currentTime; -1 when none. */
    fun activeIndex(lines: List<LrcLine>, currentTime: Double): Int {
        var idx = -1
        for (i in lines.indices) {
            if (lines[i].time <= currentTime) idx = i else break
        }
        return idx
    }
}
