package com.zprolab.FreePlayer

import com.zprolab.FreePlayer.util.LrcLine
import com.zprolab.FreePlayer.util.LrcParser
import org.junit.Assert.assertEquals
import org.junit.Test
import java.nio.charset.Charset

class LrcParserTest {

    @Test
    fun parsesMmSsXxAndMmSs() {
        val content = "[00:12.34]first line\n[00:15]second line\n"
        val lines = LrcParser.parse(content)
        assertEquals(2, lines.size)
        assertEquals(12.34, lines[0].time, 0.001)
        assertEquals("first line", lines[0].text)
        assertEquals(15.0, lines[1].time, 0.001)
    }

    @Test
    fun centisecondsPadLikeDesktop() {
        // "3" pads to "30" -> 0.30; "345" slices to "34" -> 0.34
        assertEquals(10.30, LrcParser.parse("[00:10.3]x\n").first().time, 0.001)
        assertEquals(10.34, LrcParser.parse("[00:10.345]x\n").first().time, 0.001)
    }

    @Test
    fun colonOrDotForCentiseconds() {
        val content = "[01:02:03]colon\n[01:02.03]dot\n"
        val lines = LrcParser.parse(content)
        assertEquals(2, lines.size)
        assertEquals(1 * 60 + 2 + 0.03, lines[0].time, 0.001)
        assertEquals(1 * 60 + 2 + 0.03, lines[1].time, 0.001)
    }

    @Test
    fun multipleTimeTagsExpandThenDedupe() {
        // three tags, same text -> adjacent duplicates merged to one entry
        val content = "[00:10][00:20][00:30]chorus\n"
        val lines = LrcParser.parse(content)
        assertEquals(1, lines.size)
        assertEquals(10.0, lines[0].time, 0.001)
        assertEquals("chorus", lines[0].text)
    }

    @Test
    fun metadataLinesAreSkipped() {
        val content = "[ti:Some Song]\n[ar:Some Artist]\n[00:10]real line\n"
        val lines = LrcParser.parse(content)
        assertEquals(1, lines.size)
        assertEquals("real line", lines[0].text)
    }

    @Test
    fun emptyTextLinesAreSkipped() {
        val content = "[00:10]\n[00:20]hello\n"
        val lines = LrcParser.parse(content)
        assertEquals(1, lines.size)
    }

    @Test
    fun sortedByTimeAndAdjacentDuplicatesRemoved() {
        val content = "[00:30]b\n[00:10]a\n[00:20]b\n[00:40]b\n"
        val lines = LrcParser.parse(content)
        assertEquals(listOf(10.0, 20.0), lines.map { it.time })
        assertEquals(listOf("a", "b"), lines.map { it.text })
    }

    @Test
    fun activeIndexPicksLastLineAtOrBeforeTime() {
        val lines = listOf(
            LrcLine(5.0, "a"),
            LrcLine(10.0, "b"),
            LrcLine(15.0, "c"),
        )
        assertEquals(-1, LrcParser.activeIndex(lines, 0.0))
        assertEquals(0, LrcParser.activeIndex(lines, 5.0))
        assertEquals(1, LrcParser.activeIndex(lines, 12.0))
        assertEquals(2, LrcParser.activeIndex(lines, 99.0))
    }

    @Test
    fun sanitizeRemovesControlAndZeroWidthChars() {
        val result = LrcParser.sanitizeText("a\u200Bb\u200cc")
        assertEquals("a b c", result)
    }

    @Test
    fun decodeUtf8() {
        val raw = "[00:10]中文歌词\n".toByteArray(Charsets.UTF_8)
        val decoded = LrcParser.decodeLrc(raw)
        assertEquals("[00:10]中文歌词", decoded.trim())
    }

    @Test
    fun decodeGb18030() {
        val raw = "[00:10]中文歌词\n".toByteArray(Charset.forName("GB18030"))
        val decoded = LrcParser.decodeLrc(raw)
        assertEquals("[00:10]中文歌词", decoded.trim())
    }

    @Test
    fun decodeShiftJis() {
        val raw = "[00:10]日本語の歌詞\n".toByteArray(Charset.forName("Shift_JIS"))
        val decoded = LrcParser.decodeLrc(raw)
        assertEquals("[00:10]日本語の歌詞", decoded.trim())
    }
}
