package com.mediahro.mediahro.platform.tls

import javax.net.ssl.SSLException

/**
 * The fixed TLS profile of Mediahro-to-Mediahro mutual TLS (NET-017). It runs
 * on TLS 1.2 only, because there the server refuses an unpaired client during
 * the handshake (in TLS 1.3 the client finishes first and sees the refusal on
 * its first read). TLS 1.2 is acceptable only with forward-secret AEAD suites,
 * so nothing else is ever enabled: no CBC, no static RSA key exchange, no
 * SHA-1. Pure Kotlin so the set is unit-tested.
 */
internal object MutualTls {
    val PROTOCOLS = listOf("TLSv1.2")

    /** In order of preference. */
    val SUITES = listOf(
        "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256",
        "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256",
        "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384",
        "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384",
        "TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256",
        "TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256",
    )

    /**
     * [SUITES] that [supported] contains. Throws [SSLException] when none is
     * left, so a listener or a connection fails instead of falling back to
     * something weaker.
     */
    fun select(supported: Array<String>): Array<String> {
        val have = supported.toSet()
        val chosen = SUITES.filter { it in have }
        if (chosen.isEmpty()) throw SSLException("no forward-secret AEAD cipher suite is available for mutual TLS")
        return chosen.toTypedArray()
    }
}
