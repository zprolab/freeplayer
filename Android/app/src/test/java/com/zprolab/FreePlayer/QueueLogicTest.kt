package com.zprolab.FreePlayer

import com.zprolab.FreePlayer.playback.QueueLogic
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 1:1 port of the main version's tests/playback.test.js
 * (getNextIndex / getPrevIndex contracts).
 */
class QueueLogicTest {

    private val queue = listOf(1L, 2L, 3L, 4L)

    @Test
    fun sequentialNext() {
        assertEquals(1, QueueLogic.getNextIndex(queue, 0, "sequential", emptyList()))
        assertEquals(3, QueueLogic.getNextIndex(queue, 2, "sequential", emptyList()))
    }

    @Test
    fun sequentialNextWrapsToFirst() {
        assertEquals(0, QueueLogic.getNextIndex(queue, 3, "sequential", emptyList()))
    }

    @Test
    fun sequentialPrev() {
        assertEquals(1, QueueLogic.getPrevIndex(queue, 2, 1.0, "sequential", emptyList()))
    }

    @Test
    fun sequentialPrevWrapsToLast() {
        assertEquals(3, QueueLogic.getPrevIndex(queue, 0, 1.0, "sequential", emptyList()))
    }

    @Test
    fun prevRestartsCurrentTrackAfter3Seconds() {
        assertEquals(1, QueueLogic.getPrevIndex(queue, 1, 4.0, "sequential", emptyList()))
    }

    @Test
    fun repeatOneNextKeepsIndex() {
        assertEquals(1, QueueLogic.getNextIndex(queue, 1, "repeat-one", emptyList()))
    }

    @Test
    fun shuffleNextStaysInBounds() {
        val shuffled = QueueLogic.shuffleArray(queue)
        val idx = QueueLogic.getNextIndex(queue, 1, "shuffle", shuffled)
        assertTrue("next idx out of bounds", idx in 0 until queue.size)
    }

    @Test
    fun shufflePrevStaysInBounds() {
        val shuffled = QueueLogic.shuffleArray(queue)
        val idx = QueueLogic.getPrevIndex(queue, 1, 1.0, "shuffle", shuffled)
        assertTrue("prev idx out of bounds", idx in 0 until queue.size)
    }

    @Test
    fun emptyQueueReturnsMinusOne() {
        assertEquals(-1, QueueLogic.getNextIndex(emptyList(), 0, "sequential", emptyList()))
        assertEquals(-1, QueueLogic.getPrevIndex(emptyList(), 0, 1.0, "sequential", emptyList()))
    }

    @Test
    fun shuffleNeverMutatesInput() {
        val original = queue.toList()
        QueueLogic.shuffleArray(queue)
        assertEquals(original, queue)
    }

    @Test
    fun shuffleIsAPermutation() {
        val shuffled = QueueLogic.shuffleArray(queue)
        assertEquals(queue.sorted(), shuffled.sorted())
    }
}
