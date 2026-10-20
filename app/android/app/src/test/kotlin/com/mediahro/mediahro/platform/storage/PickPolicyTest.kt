package com.mediahro.mediahro.platform.storage

import com.mediahro.mediahro.pigeon.PickKindMsg
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PickPolicyTest {
    private val ext = mapOf("video/mp4" to "mp4", "image/jpeg" to "jpg")::get

    @Test
    fun `SYS-007 video picks use the documents picker, not the Photo Picker`() {
        assertEquals(PickPolicy.Picker.DOCUMENTS, PickPolicy.pickerFor(listOf(PickKindMsg.VIDEO)))
        assertEquals(
            PickPolicy.Picker.DOCUMENTS,
            PickPolicy.pickerFor(listOf(PickKindMsg.IMAGE, PickKindMsg.VIDEO)),
        )
        assertEquals(PickPolicy.Picker.DOCUMENTS, PickPolicy.pickerFor(emptyList()))
    }

    @Test
    fun `SYS-007 image-only picks use the Photo Picker`() {
        assertEquals(PickPolicy.Picker.PHOTO_PICKER, PickPolicy.pickerFor(listOf(PickKindMsg.IMAGE)))
    }

    @Test
    fun `FILE-001 video picks accept MKV typed as octet-stream`() {
        val mimes = PickPolicy.mimeTypes(listOf(PickKindMsg.VIDEO)).toList()
        assertTrue(mimes.contains("video/*"))
        assertTrue(mimes.contains("application/x-matroska"))
        assertTrue(mimes.contains("application/octet-stream"))
        assertArrayEquals(arrayOf("*/*"), PickPolicy.mimeTypes(listOf(PickKindMsg.SUBTITLE)))
        assertArrayEquals(arrayOf("*/*"), PickPolicy.mimeTypes(emptyList()))
    }

    @Test
    fun `SYS-007 picked files keep their display name`() {
        assertEquals("Holiday.mkv", PickPolicy.displayName(listOf("Holiday.mkv"), "1000000123", "video/mp4", ext))
    }

    @Test
    fun `SYS-007 a bare media id is never the name`() {
        // Photo Picker / OEM gallery URI whose query gave only the id.
        assertEquals(
            "1000000123.mp4",
            PickPolicy.displayName(listOf("1000000123", null, " "), "1000000123", "video/mp4", ext),
        )
        assertEquals("1000000123", PickPolicy.displayName(emptyList(), "1000000123", null, ext))
    }

    @Test
    fun `SYS-007 a file-like last segment is used when the provider gives no name`() {
        assertEquals("clip.mp4", PickPolicy.displayName(listOf(null), "primary:Movies/clip.mp4", "video/mp4", ext))
    }
}
