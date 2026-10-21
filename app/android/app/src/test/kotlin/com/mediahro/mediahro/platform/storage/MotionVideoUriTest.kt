package com.mediahro.mediahro.platform.storage

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MotionVideoUriTest {
    private val asset = "content://media/external/images/media/1234"

    @Test
    fun `IMG-016 the served URI round trips the asset id as one path segment`() {
        val uri = MotionVideoUri.build("com.mediahro.app.motion", asset)
        assertTrue(uri.startsWith("content://com.mediahro.app.motion/"))
        val segment = uri.removePrefix("content://com.mediahro.app.motion/")
        assertFalse("one segment, no raw slash", segment.contains('/'))
        assertEquals(asset, MotionVideoUri.assetOf(segment))
    }

    @Test
    fun `IMG-016 only MediaStore assets can be served`() {
        assertTrue(MotionVideoUri.isServable(asset))
        assertFalse(MotionVideoUri.isServable("file:///data/data/com.mediahro.app/secret.jpg"))
        assertFalse(MotionVideoUri.isServable("content://com.android.providers.downloads.documents/document/5"))
        assertFalse(MotionVideoUri.isServable("content://media/"))
        assertFalse(MotionVideoUri.isServable(""))
        try {
            MotionVideoUri.build("a.motion", "file:///etc/hosts")
            org.junit.Assert.fail("expected an IllegalArgumentException")
        } catch (e: IllegalArgumentException) {
            // refused
        }
    }

    @Test
    fun `IMG-016 a path that decodes to something else is not served`() {
        assertNull(MotionVideoUri.assetOf(null))
        assertNull(MotionVideoUri.assetOf(""))
        assertNull(MotionVideoUri.assetOf("file%3A%2F%2F%2Fdata%2Fsecret"))
        assertNull(MotionVideoUri.assetOf("content%3A%2F%2Fother%2F1"))
        assertNull(MotionVideoUri.assetOf("%E0%A4%A"))
    }
}
