package com.zprolab.FreePlayer.playback

/**
 * Pure queue algorithms — 1:1 port of the main version's playback.test.js
 * (getNextIndex / getPrevIndex / shuffleArray).
 */
object QueueLogic {

    const val MODE_SEQUENTIAL = "sequential"
    const val MODE_REPEAT_ONE = "repeat-one"
    const val MODE_SHUFFLE = "shuffle"

    /** Fisher–Yates shuffle; never mutates the input array. */
    fun shuffleArray(array: List<Long>): List<Long> {
        val a = array.toMutableList()
        for (i in a.size - 1 downTo 1) {
            val j = (Math.random() * (i + 1)).toInt()
            val tmp = a[i]
            a[i] = a[j]
            a[j] = tmp
        }
        return a
    }

    /**
     * Next index in the queue. Empty queue -> -1.
     * repeat-one -> same index (loop the current track forever).
     * shuffle -> walk the shuffled order, mapping back to queue indices by track id;
     *            at the end wrap around to the first shuffled entry.
     * sequential -> queueIndex+1, wrapping to 0.
     */
    fun getNextIndex(
        queue: List<Long>,
        queueIndex: Int,
        playMode: String,
        shuffledQueue: List<Long>,
    ): Int {
        if (queue.isEmpty()) return -1
        if (playMode == MODE_REPEAT_ONE) return queueIndex
        if (playMode == MODE_SHUFFLE) {
            val shuffled = if (shuffledQueue.isNotEmpty()) shuffledQueue else queue
            val current = queue[queueIndex]
            val curIdx = shuffled.indexOf(current)
            if (curIdx < shuffled.size - 1) {
                return queue.indexOf(shuffled[curIdx + 1])
            }
            return queue.indexOf(shuffled[0])
        }
        return if (queueIndex < queue.size - 1) queueIndex + 1 else 0
    }

    /**
     * Previous index. Empty queue -> -1.
     * currentTime > 3 -> restart the current track (same index).
     * shuffle -> previous shuffled entry (wraps to last).
     * sequential -> queueIndex-1 (wraps to last).
     */
    fun getPrevIndex(
        queue: List<Long>,
        queueIndex: Int,
        currentTime: Double,
        playMode: String,
        shuffledQueue: List<Long>,
    ): Int {
        if (queue.isEmpty()) return -1
        if (currentTime > 3) return queueIndex
        if (playMode == MODE_SHUFFLE) {
            val shuffled = if (shuffledQueue.isNotEmpty()) shuffledQueue else queue
            val current = queue[queueIndex]
            val curIdx = shuffled.indexOf(current)
            if (curIdx > 0) {
                return queue.indexOf(shuffled[curIdx - 1])
            }
            return queue.indexOf(shuffled[shuffled.size - 1])
        }
        return if (queueIndex > 0) queueIndex - 1 else queue.size - 1
    }
}
