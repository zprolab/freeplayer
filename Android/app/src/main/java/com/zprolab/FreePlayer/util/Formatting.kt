package com.zprolab.FreePlayer.util

import java.util.Locale

object Formatting {

    /** m:ss format (desktop: formatTime, e.g. "3:05", invalid -> "--:--"). */
    fun formatTime(seconds: Double): String {
        if (!seconds.isFinite() || seconds < 0) return "--:--"
        val total = seconds.toInt()
        val m = total / 60
        val s = total % 60
        return "$m:${s.toString().padStart(2, '0')}"
    }

    /** m:ss with zero -> "0:00" (library duration column treats invalid as "--:--"). */
    fun formatTrackDuration(seconds: Double): String {
        if (seconds <= 0) return "--:--"
        return formatTime(seconds)
    }

    /** Xh Ym / Xm / 0m (stats). */
    fun formatDurationLong(seconds: Double): String {
        val total = seconds.toInt()
        val h = total / 3600
        val m = (total % 3600) / 60
        return when {
            h > 0 -> "${h}h ${m}m"
            m > 0 -> "${m}m"
            else -> "0m"
        }
    }

    fun formatFileSize(bytes: Long): String {
        if (bytes < 1024) return "$bytes B"
        val kb = bytes / 1024.0
        if (kb < 1024) return String.format(Locale.US, "%.1f KB", kb)
        val mb = kb / 1024.0
        if (mb < 1024) return String.format(Locale.US, "%.1f MB", mb)
        return String.format(Locale.US, "%.1f GB", mb / 1024.0)
    }

    /** "1411 kbps" / "48.0 kHz" */
    fun formatBitrate(kbps: Int?): String? = kbps?.let { "$it kbps" }

    fun formatSampleRate(hz: Int?): String? = hz?.let { String.format(Locale.US, "%.1f kHz", it / 1000.0) }

    /** "Mar 5" from ISO "YYYY-MM-DD HH:MM:SS" (imported_at). */
    fun formatImportedAt(datetime: String): String {
        val datePart = datetime.substringBefore(' ')
        val parts = datePart.split("-")
        if (parts.size != 3) return datetime
        val months = listOf(
            "Jan", "Feb", "Mar", "Apr", "May", "Jun",
            "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
        )
        val month = parts[1].toIntOrNull()?.let { months.getOrNull(it - 1) } ?: return datetime
        val day = parts[2].toIntOrNull() ?: return datetime
        return "$month $day, ${parts[0]}"
    }

    /**
     * "Mon D, h:mm AM/PM" for recent plays (desktop toLocaleString
     * with month short, day numeric, hour/minute 2-digit).
     */
    fun formatStartedAt(datetime: String): String {
        val parsed = runCatching {
            java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US)
                .parse(datetime) ?: return@runCatching null
        }.getOrNull() ?: return formatImportedAt(datetime)
        return java.text.SimpleDateFormat("MMM d, h:mm a", Locale.US).format(parsed)
    }
}
