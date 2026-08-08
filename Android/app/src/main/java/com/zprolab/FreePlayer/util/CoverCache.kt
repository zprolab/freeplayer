package com.zprolab.FreePlayer.util

/**
 * Port of coverCache.js — LRU cache capped at 50 entries.
 * Thread-safe: CoverArt reads/writes from IO threads concurrently.
 */
object CoverCache {

    private val cache = object : LinkedHashMap<String, ByteArray>(0, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, ByteArray>?): Boolean {
            return size > MAX_ENTRIES
        }
    }

    private const val MAX_ENTRIES = 50

    @Synchronized
    fun getCachedCover(path: String): ByteArray? = cache[path]

    @Synchronized
    fun setCachedCover(path: String, data: ByteArray) {
        cache[path] = data
    }

    @Synchronized
    fun clearCoverCache() = cache.clear()
}
