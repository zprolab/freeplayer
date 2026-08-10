package com.zprolab.FreePlayer.data

data class Track(
    val id: Long,
    val title: String,
    val artist: String,
    val album: String,
    val trackNumber: Int?,
    val discNumber: Int?,
    val genre: String?,
    val year: Int?,
    val duration: Double,
    val filePath: String,
    val fileName: String,
    val fileSize: Long,
    val fileFormat: String?,
    val bitrate: Int?,
    val sampleRate: Int?,
    val channels: Int?,
    val coverPath: String?,
    val replaygainGain: Double,
    val replaygainPeak: Double,
    val importedAt: String,
    val updatedAt: String,
    val lrcPath: String?,
    val position: Int? = null,
    val addedToPlaylistAt: String? = null,
) {
    val displayTitle: String get() = title.ifEmpty { fileName }

    companion object {
        const val UNKNOWN_ARTIST = "Unknown Artist"
        const val UNKNOWN_ALBUM = "Unknown Album"
    }
}

data class Playlist(
    val id: Long,
    val name: String,
    val description: String?,
    val createdAt: String,
    val updatedAt: String,
)

data class PlayHistoryEntry(
    val id: Long,
    val trackId: Long,
    val startedAt: String,
    val endedAt: String?,
    val durationSeconds: Double,
    val playPercentage: Double,
    val title: String,
    val artist: String,
    val album: String,
    val filePath: String,
    val trackDuration: Double,
)

data class TopTrackStat(
    val id: Long,
    val title: String,
    val artist: String,
    val album: String,
    val trackDuration: Double,
    val playCount: Int,
    val totalListenTime: Double,
)

data class TopArtistStat(
    val artist: String,
    val playCount: Int,
    val totalListenTime: Double,
)

data class DailyStat(
    val date: String,
    val plays: Int,
    val totalTime: Double,
)

data class ListeningStats(
    val totalTime: Double,
    val totalPlays: Long,
    val uniqueTracksPlayed: Long,
    val topTracks: List<TopTrackStat>,
    val topArtists: List<TopArtistStat>,
    val dailyStats: List<DailyStat>,
)

data class ImportResult(
    val imported: Int,
    val skipped: Int,
    val errors: List<Pair<String, String>>,
)

enum class FetchState { IDLE, FETCHING, NOT_FOUND, FAILED }
