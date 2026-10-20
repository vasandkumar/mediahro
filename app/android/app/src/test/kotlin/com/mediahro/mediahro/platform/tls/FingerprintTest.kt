package com.mediahro.mediahro.platform.tls

import org.junit.Assert.assertEquals
import org.junit.Test

class FingerprintTest {
    @Test
    fun `NET-004 pins match whatever the case and colons`() {
        val shown = "AB:CD:EF:01"
        assertEquals("ABCDEF01", Fingerprint.normalize(shown))
        assertEquals(Fingerprint.normalize(shown), Fingerprint.normalize("abcdef01"))
        assertEquals(Fingerprint.normalize(shown), Fingerprint.normalize("ab:cd:ef:01"))
        assertEquals(Fingerprint.normalize(shown), Fingerprint.normalize("AB CD EF 01"))
    }
}
