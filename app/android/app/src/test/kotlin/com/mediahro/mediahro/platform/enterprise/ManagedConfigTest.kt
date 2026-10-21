package com.mediahro.mediahro.platform.enterprise

import com.mediahro.mediahro.pigeon.ManagedKindMsg
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ManagedConfigTest {
    @Test
    fun `B2B-001 restriction values map to typed entries sorted by key`() {
        val entries = ManagedConfigModule.convert(
            mapOf(
                "playlist_url" to "https://example.test/list.m3u",
                "kiosk" to true,
                "volume_cap" to 80,
                "big" to 5_000_000_000L,
                "allowed_sources" to arrayOf("smb", "sftp"),
                "tags" to listOf("a", "b"),
            ),
        )
        assertEquals(listOf("allowed_sources", "big", "kiosk", "playlist_url", "tags", "volume_cap"), entries.map { it.key })
        val byKey = entries.associateBy { it.key }
        assertEquals(ManagedKindMsg.LIST, byKey.getValue("allowed_sources").kind)
        assertEquals(listOf("smb", "sftp"), byKey.getValue("allowed_sources").listValue)
        assertEquals(5_000_000_000L, byKey.getValue("big").intValue)
        assertEquals(true, byKey.getValue("kiosk").boolValue)
        assertEquals(80L, byKey.getValue("volume_cap").intValue)
        assertNull(byKey.getValue("kiosk").stringValue)
    }

    @Test
    fun `B2B-001 nested bundles, mixed lists and nulls are dropped`() {
        val entries = ManagedConfigModule.convert(
            mapOf(
                "nested" to Object(),
                "mixed" to listOf("a", 1),
                "none" to null,
                "ok" to "x",
            ),
        )
        assertEquals(listOf("ok"), entries.map { it.key })
    }
}
