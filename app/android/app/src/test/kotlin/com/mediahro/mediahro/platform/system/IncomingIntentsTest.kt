package com.mediahro.mediahro.platform.system

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class IncomingIntentsTest {
    @Test
    fun `SYS-004 a shared text's link is found and trimmed`() {
        assertEquals(
            "https://example.com/live/index.m3u8",
            IncomingIntents.linkTextIn("Watch this: https://example.com/live/index.m3u8."),
        )
        assertEquals("rtsp://192.168.1.20:554/stream1", IncomingIntents.linkTextIn("cam (rtsp://192.168.1.20:554/stream1)"))
        assertEquals("http://nas.local/a.mkv", IncomingIntents.linkTextIn("http://nas.local/a.mkv\nsecond http://x/y"))
    }

    @Test
    fun `SYS-004 plain text without a link is not an open request`() {
        assertNull(IncomingIntents.linkTextIn("just a note"))
        assertNull(IncomingIntents.linkTextIn("ftp-like: notalink://x"))
    }
}
