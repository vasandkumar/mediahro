package com.mediahro.mediahro.platform.tls

import android.annotation.SuppressLint
import java.net.Socket
import java.security.KeyStore
import java.security.MessageDigest
import java.security.Principal
import java.security.PrivateKey
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import javax.net.ssl.SSLEngine
import javax.net.ssl.TrustManagerFactory
import javax.net.ssl.X509ExtendedKeyManager
import javax.net.ssl.X509TrustManager

/** Certificate fingerprints as the app shows them: `AB:CD:…` (SHA-256 of the DER). */
internal object Fingerprint {
    fun of(cert: X509Certificate): String =
        MessageDigest.getInstance("SHA-256").digest(cert.encoded).joinToString(":") { "%02X".format(it) }

    /** Accepts `ab:cd…`, `ABCD…` or any mix of case and colons. */
    fun normalize(fp: String): String = fp.replace(":", "").replace(" ", "").uppercase()

    fun matches(cert: X509Certificate, pin: String?): Boolean =
        pin != null && normalize(of(cert)) == normalize(pin)
}

/**
 * Client trust (docs/05 §9): the system's CAs, or a certificate the user
 * confirmed by fingerprint ([pin]). An untrusted, unpinned peer fails the
 * handshake and [rejectedFingerprint] says what to show the user.
 */
@SuppressLint("CustomX509TrustManager")
internal class PinningTrustManager(private val pin: String?) : X509TrustManager {
    private val system: X509TrustManager = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm())
        .apply { init(null as KeyStore?) }
        .trustManagers.filterIsInstance<X509TrustManager>().first()

    @Volatile var rejectedFingerprint: String? = null
        private set

    /** True when the pin, not the system, accepted the peer (skip hostname checks). */
    @Volatile var acceptedByPin = false
        private set

    override fun checkServerTrusted(chain: Array<out X509Certificate>, authType: String) {
        val leaf = chain.firstOrNull() ?: throw CertificateException("empty chain")
        if (Fingerprint.matches(leaf, pin)) {
            acceptedByPin = true
            return
        }
        try {
            system.checkServerTrusted(chain, authType)
        } catch (e: CertificateException) {
            rejectedFingerprint = Fingerprint.of(leaf)
            throw e
        }
    }

    override fun checkClientTrusted(chain: Array<out X509Certificate>, authType: String) =
        throw CertificateException("client certificates are not accepted here")

    override fun getAcceptedIssuers(): Array<X509Certificate> = system.acceptedIssuers
}

/**
 * Mutual-TLS trust for Mediahro-to-Mediahro sharing (NET-017): only peers
 * whose certificate fingerprint is in [trusted] (paired by QR); no CAs.
 */
@SuppressLint("CustomX509TrustManager")
internal class PeerSetTrustManager(@Volatile var trusted: Set<String>) : X509TrustManager {
    private fun check(chain: Array<out X509Certificate>) {
        val leaf = chain.firstOrNull() ?: throw CertificateException("empty chain")
        val fp = Fingerprint.normalize(Fingerprint.of(leaf))
        if (trusted.none { Fingerprint.normalize(it) == fp }) throw CertificateException("peer not paired: $fp")
    }

    override fun checkClientTrusted(chain: Array<out X509Certificate>, authType: String) = check(chain)

    override fun checkServerTrusted(chain: Array<out X509Certificate>, authType: String) = check(chain)

    override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
}

/** Presents one Keystore identity (key never leaves the Keystore). */
internal class IdentityKeyManager(
    private val alias: String,
    private val key: PrivateKey,
    private val chain: Array<X509Certificate>,
) : X509ExtendedKeyManager() {
    override fun getClientAliases(keyType: String?, issuers: Array<out Principal>?) = arrayOf(alias)

    override fun chooseClientAlias(keyType: Array<out String>?, issuers: Array<out Principal>?, socket: Socket?) = alias

    override fun getServerAliases(keyType: String?, issuers: Array<out Principal>?) = arrayOf(alias)

    override fun chooseServerAlias(keyType: String?, issuers: Array<out Principal>?, socket: Socket?) = alias

    override fun chooseEngineClientAlias(keyType: Array<out String>?, issuers: Array<out Principal>?, engine: SSLEngine?) =
        alias

    override fun chooseEngineServerAlias(keyType: String?, issuers: Array<out Principal>?, engine: SSLEngine?) = alias

    override fun getCertificateChain(alias: String?): Array<X509Certificate> = chain

    override fun getPrivateKey(alias: String?): PrivateKey = key
}
