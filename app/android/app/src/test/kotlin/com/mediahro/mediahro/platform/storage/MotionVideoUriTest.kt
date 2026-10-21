package com.mediahro.mediahro.platform.storage

import java.net.URI
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MotionVideoUriTest {
    private val asset = "content://media/external/images/media/1234"

    /** What Android's `Uri.lastPathSegment` returns for a served URI: the segment decoded once. */
    private fun lastPathSegment(uri: String): String = URI(uri).path.removePrefix("/")

    @Test
    fun `IMG-016 the served URI round trips the asset id as one path segment`() {
        val uri = MotionVideoUri.build("com.mediahro.app.motion", asset)
        assertTrue(uri.startsWith("content://com.mediahro.app.motion/"))
        val segment = uri.removePrefix("content://com.mediahro.app.motion/")
        assertFalse("one segment, no raw slash", segment.contains('/'))
        // The provider receives the segment decoded once and must not decode it again.
        assertEquals(asset, MotionVideoUri.assetOf(lastPathSegment(uri)))
    }

    @Test
    fun `IMG-016 the encoding is plain percent encoding, a space is %20 and a plus stays a plus`() {
        assertEquals("a%20b%2Bc", MotionVideoUri.percentEncode("a b+c"))
        assertEquals("%C3%A9-._~", MotionVideoUri.percentEncode("\u00e9-._~"))
        assertEquals("content%3A%2F%2Fmedia%2Fx", MotionVideoUri.percentEncode("content://media/x"))
        // Decoding twice would turn %2B into + into a space; the provider decodes once.
        assertEquals("a+b", URI("x://h/" + MotionVideoUri.percentEncode("a+b")).path.removePrefix("/"))
    }

    @Test
    fun `IMG-016 only MediaStore images can be served`() {
        assertTrue(MotionVideoUri.isServable(asset))
        assertTrue(MotionVideoUri.isServable("content://media/external_primary/images/media/7"))
        assertFalse(MotionVideoUri.isServable("content://media/external/video/media/1234"))
        assertFalse(MotionVideoUri.isServable("content://media/external/audio/media/1234"))
        assertFalse(MotionVideoUri.isServable("content://media/external/file/1234"))
        assertFalse(MotionVideoUri.isServable("content://media/external/images/media/12x"))
        assertFalse(MotionVideoUri.isServable("content://media/external/images/media/12/../34"))
        assertFalse(MotionVideoUri.isServable("content://media/external/images/media/"))
        assertFalse(MotionVideoUri.isServable("file:///data/data/com.mediahro.app/secret.jpg"))
        assertFalse(MotionVideoUri.isServable("content://com.android.providers.downloads.documents/document/5"))
        assertFalse(MotionVideoUri.isServable("content://media/"))
        assertFalse(MotionVideoUri.isServable(""))
        try {
            MotionVideoUri.build("a.motion", "content://media/external/video/media/1")
            org.junit.Assert.fail("expected an IllegalArgumentException")
        } catch (e: IllegalArgumentException) {
            // refused
        }
    }

    @Test
    fun `IMG-016 a segment that is not a servable asset is not served`() {
        assertNull(MotionVideoUri.assetOf(null))
        assertNull(MotionVideoUri.assetOf(""))
        assertNull(MotionVideoUri.assetOf("file:///data/secret"))
        assertNull(MotionVideoUri.assetOf("content://other/1"))
        // A still-encoded id is not an asset either: it was not decoded once too few.
        assertNull(MotionVideoUri.assetOf("content%3A%2F%2Fmedia%2Fexternal%2Fimages%2Fmedia%2F1"))
    }
}
