package com.mediahro.mediahro.platform.storage

import java.nio.ByteBuffer
import java.nio.channels.FileChannel

/**
 * Motion Photo video component (IMG-016 Live/Motion pairing): Google
 * Motion Photo v1 (`Container:Directory` item with `Semantic="MotionPhoto"`),
 * the older MicroVideo XMP (`GCamera:MicroVideoOffset`) and Samsung's
 * `MotionPhoto_Data` trailer. The video is the file's tail, so it is copied
 * out without decoding.
 */
internal object MotionPhoto {
    private const val HEAD = 256 * 1024
    private val microVideoOffset = Regex("""MicroVideoOffset\s*=\s*"(\d+)"""")
    private val motionItem = Regex(
        """Semantic\s*=\s*"MotionPhoto"[^>]*?Length\s*=\s*"(\d+)"(?:[^>]*?Padding\s*=\s*"(\d+)")?""",
    )
    private val motionItemReversed = Regex(
        """Length\s*=\s*"(\d+)"[^>]*?Semantic\s*=\s*"MotionPhoto"""",
    )
    private val samsungMarker = "MotionPhoto_Data".toByteArray(Charsets.ISO_8859_1)

    /** Heuristic for list views; [videoRange] decides. */
    fun looksLikeMotionPhoto(name: String): Boolean =
        name.startsWith("MVIMG_") || name.contains(".MP.") || name.endsWith(".MP.jpg", ignoreCase = true)

    /** Byte range of the embedded video, or null when there is none. */
    fun videoRange(channel: FileChannel): LongRange? {
        val size = channel.size()
        if (size < 16) return null
        val head = read(channel, 0, minOf(size, HEAD.toLong()).toInt())
        val xmp = String(head, Charsets.ISO_8859_1)
        val length: Long? =
            motionItem.find(xmp)?.let { it.groupValues[1].toLong() + (it.groupValues[2].toLongOrNull() ?: 0) }
                ?: motionItemReversed.find(xmp)?.groupValues?.get(1)?.toLong()
                ?: microVideoOffset.find(xmp)?.groupValues?.get(1)?.toLong()
        if (length != null && length in 1 until size) {
            val start = size - length
            return if (isMp4(channel, start)) start until size else null
        }
        return samsungTrailer(channel, size)
    }

    private fun samsungTrailer(channel: FileChannel, size: Long): LongRange? {
        // The marker sits shortly before the video near the end of the file;
        // scan the last 32 MB in 1 MB windows overlapping by the marker size.
        val window = 1 shl 20
        var end = size
        val floor = maxOf(0L, size - 32L * window)
        while (end > floor) {
            val start = maxOf(floor, end - window)
            val buf = read(channel, start, (end - start).toInt())
            val i = lastIndexOf(buf, samsungMarker)
            if (i >= 0) {
                val video = start + i + samsungMarker.size
                return if (video < size && isMp4(channel, video)) video until size else null
            }
            end = start + samsungMarker.size - 1
            if (start == floor) break
        }
        return null
    }

    private fun isMp4(channel: FileChannel, offset: Long): Boolean {
        if (offset + 8 > channel.size()) return false
        val box = read(channel, offset + 4, 4)
        return String(box, Charsets.ISO_8859_1) == "ftyp"
    }

    private fun read(channel: FileChannel, offset: Long, length: Int): ByteArray {
        val buf = ByteBuffer.allocate(length)
        var pos = offset
        while (buf.hasRemaining()) {
            val n = channel.read(buf, pos)
            if (n <= 0) break
            pos += n
        }
        return buf.array().copyOf(buf.position())
    }

    private fun lastIndexOf(haystack: ByteArray, needle: ByteArray): Int {
        outer@ for (i in haystack.size - needle.size downTo 0) {
            for (j in needle.indices) if (haystack[i + j] != needle[j]) continue@outer
            return i
        }
        return -1
    }
}
