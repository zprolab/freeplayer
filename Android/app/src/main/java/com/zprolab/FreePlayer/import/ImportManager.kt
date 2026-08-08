package com.zprolab.FreePlayer.import

import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import com.zprolab.FreePlayer.data.Database
import com.zprolab.FreePlayer.data.ImportResult
import com.zprolab.FreePlayer.data.Track
import com.zprolab.FreePlayer.metadata.MetadataExtractor
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.nio.file.Files

data class ImportSource(
    val uri: Uri,
    val displayName: String,
    val relativePath: String,
    val isDirectory: Boolean,
)

/**
 * Import pipeline — Android counterpart of bridge.mm importFiles/scanDirectory.
 * Sources come from the SAF file picker (content URIs); files are copied into
 * the app-owned library directory under Artist/Album structure.
 */
object ImportManager {

    val LIBRARY_DIR_NAME = "library"

    fun libraryDir(context: Context): String {
        val settings = Database.get(context).getSetting("library_dir", null)
        if (settings != null) return settings
        val dir = File(context.getExternalFilesDir(null), LIBRARY_DIR_NAME)
        dir.mkdirs()
        val path = dir.absolutePath
        Database.get(context).setSetting("library_dir", path)
        return path
    }

    /** Recursively scan a SAF tree for audio files. Returns flattened list. */
    suspend fun scanTree(context: Context, treeUri: Uri): List<ImportSource> =
        withContext(Dispatchers.IO) {
            val resolver = context.contentResolver
            val root = treeUri.takeIf { DocumentsContract.isTreeUri(it) }
            val out = mutableListOf<ImportSource>()
            val rootDocId = DocumentsContract.getTreeDocumentId(treeUri)
            scanDocument(resolver, treeUri, rootDocId, "", out)
            out
        }

    private fun scanDocument(
        resolver: android.content.ContentResolver,
        treeUri: Uri,
        docId: String,
        relativePath: String,
        out: MutableList<ImportSource>,
    ) {
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, docId)
        val nameProjection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
        )
        try {
            resolver.query(childrenUri, nameProjection, null, null, null)?.use { cursor ->
                while (cursor.moveToNext()) {
                    val childId = cursor.getString(0) ?: continue
                    val displayName = cursor.getString(1) ?: continue
                    if (displayName.startsWith(".")) continue // hidden dirs/files
                    val mime = cursor.getString(2) ?: ""
                    val childRel = if (relativePath.isEmpty()) displayName else "$relativePath/$displayName"
                    if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                        scanDocument(resolver, treeUri, childId, childRel, out)
                    } else if (MetadataExtractor.isAudioFile(displayName)) {
                        val uri = DocumentsContract.buildDocumentUriUsingTree(treeUri, childId)
                        out.add(ImportSource(uri, displayName, childRel, isDirectory = false))
                    }
                }
            }
        } catch (_: Exception) {
        }
    }

    /**
     * Import files: copy into library under Artist/Album, extract metadata,
     * write cover art to <albumDir>/.covers/cover.jpg, upsert into the DB.
     */
    suspend fun importFiles(
        context: Context,
        sources: List<ImportSource>,
        importMode: String,
    ): ImportResult = withContext(Dispatchers.IO) {
        val db = Database.get(context)
        val library = libraryDir(context)
        val tempDir = File(context.cacheDir, "import").apply { mkdirs() }
        var imported = 0
        var skipped = 0
        val errors = mutableListOf<Pair<String, String>>()

        for (src in sources) {
            val baseName = src.displayName
            val tmp = File(tempDir, baseName)
            try {
                context.contentResolver.openInputStream(src.uri)?.use { input ->
                    tmp.outputStream().use { output -> input.copyTo(output) }
                } ?: run {
                    errors.add(baseName to "Unreadable audio file")
                    continue
                }

                val meta = MetadataExtractor.extractAtPath(tmp.absolutePath)
                if (meta == null) {
                    tmp.delete()
                    errors.add(baseName to "Unreadable audio file")
                    continue
                }

                val artist = meta.artist.orEmpty().replace("/", "_")
                val album = meta.album.orEmpty().replace("/", "_")
                val albumDir = File(File(File(library, artist), album), "")
                albumDir.mkdirs()
                val target = File(albumDir, baseName)
                // A stale file from an interrupted/old import is not a duplicate
                // if the database has no corresponding track row.
                if (!target.exists() && Files.isSymbolicLink(target.toPath())) {
                    target.delete()
                }
                val alreadyInDatabase = target.exists() && db.getTrackByPath(target.absolutePath) != null
                val created = if (target.exists()) {
                    false
                } else {
                    // SAF gives us a content URI, not a stable filesystem path. A
                    // symlink to the temporary cache file would become dangling
                    // as soon as the import finishes, so copy in both modes.
                    runCatching { tmp.copyTo(target, overwrite = false); true }.getOrDefault(false)
                }
                tmp.delete()

                if (!target.exists() && !created) {
                    errors.add(baseName to "Could not store audio file")
                    continue
                }

                // Cover art -> <albumDir>/.covers/cover.jpg
                var coverPath: String? = null
                val artwork = meta.artwork
                if (artwork != null && artwork.isNotEmpty()) {
                    val coverDir = File(albumDir, ".covers")
                    coverDir.mkdirs()
                    val coverFile = File(coverDir, "cover.jpg")
                    if (!coverFile.exists()) {
                        coverFile.writeBytes(artwork)
                    }
                    coverPath = coverFile.absolutePath
                }

                db.insertTrack(
                    Track(
                        id = 0,
                        title = meta.title.orEmpty(),
                        artist = meta.artist ?: "Unknown Artist",
                        album = meta.album ?: "Unknown Album",
                        trackNumber = meta.trackNumber,
                        discNumber = meta.discNumber,
                        genre = meta.genre,
                        year = meta.year,
                        duration = meta.duration,
                        filePath = target.absolutePath,
                        fileName = baseName,
                        fileSize = meta.fileSize,
                        fileFormat = meta.fileFormat,
                        bitrate = meta.bitrate,
                        sampleRate = meta.sampleRate,
                        channels = meta.channels,
                        coverPath = coverPath,
                        replaygainGain = 0.0,
                        replaygainPeak = 0.0,
                        importedAt = "",
                        updatedAt = "",
                        lrcPath = null,
                    )
                )
                if (alreadyInDatabase) skipped++ else imported++
            } catch (e: Exception) {
                errors.add(baseName to (e.message ?: "Import failed"))
            }
        }
        ImportResult(imported, skipped, errors)
    }

}
