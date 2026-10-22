package com.mediahro.mediahro.platform.storage

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DocumentsTest {
    @Test
    fun `CORE-003 a documents-provider URI answers the document columns`() {
        // content://com.android.externalstorage.documents/document/primary%3AMovies%2Fa.mkv
        assertTrue(Documents.isDocumentPath(listOf("document", "primary:Movies/a.mkv")))
        // content://com.android.externalstorage.documents/tree/primary%3AMovies/document/primary%3AMovies%2Fa.mkv
        assertTrue(Documents.isDocumentPath(listOf("tree", "primary:Movies", "document", "primary:Movies/a.mkv")))
        assertTrue(Documents.isDocumentPath(listOf("tree", "primary:Movies")))
    }

    @Test
    fun `CORE-003 a MediaStore or FileProvider URI is not a document`() {
        // content://media/external/video/media/150
        assertFalse(Documents.isDocumentPath(listOf("external", "video", "media", "150")))
        // content://com.example.fileprovider/shared/clip.mp4
        assertFalse(Documents.isDocumentPath(listOf("shared", "clip.mp4")))
        assertFalse(Documents.isDocumentPath(emptyList()))
    }
}
