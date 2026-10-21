package com.mediahro.mediahro.platform.tls

import javax.net.ssl.SSLException
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class MutualTlsTest {
    @Test
    fun `NET-017 mutual TLS is TLS 1_2 with only ECDHE AEAD suites`() {
        assertEquals(listOf("TLSv1.2"), MutualTls.PROTOCOLS)
        assertEquals(6, MutualTls.SUITES.size)
        for (s in MutualTls.SUITES) {
            assertTrue(s, s.startsWith("TLS_ECDHE_"))
            assertTrue(s, "_GCM_" in s || "_CHACHA20_POLY1305_" in s)
            assertFalse(s, "CBC" in s)
            assertFalse(s, s.endsWith("_SHA"))
        }
    }

    @Test
    fun `NET-017 only the safe suites survive from a typical supported list`() {
        val supported = arrayOf(
            "TLS_AES_128_GCM_SHA256",
            "TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA",
            "TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA",
            "TLS_RSA_WITH_AES_128_GCM_SHA256",
            "TLS_RSA_WITH_AES_256_CBC_SHA",
            "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256",
            "TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256",
            "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384",
        )
        assertArrayEquals(
            arrayOf(
                "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256",
                "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384",
                "TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256",
            ),
            MutualTls.select(supported),
        )
    }

    @Test
    fun `NET-017 with no safe suite available the connection fails`() {
        try {
            MutualTls.select(arrayOf("TLS_RSA_WITH_AES_128_CBC_SHA", "TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA"))
            fail("expected an SSLException")
        } catch (e: SSLException) {
            assertTrue(e.message!!.contains("no forward-secret"))
        }
    }
}
