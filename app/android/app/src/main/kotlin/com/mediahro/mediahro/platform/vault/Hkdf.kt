package com.mediahro.mediahro.platform.vault

import java.security.GeneralSecurityException
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/** HKDF-SHA-256 (RFC 5869) with no Android types, so it is tested against the RFC vectors. */
internal object Hkdf {
    private const val HMAC = "HmacSHA256"
    private const val HASH_BYTES = 32

    /** The label every vault derivation uses (ADR-039 amendment 2). */
    val VAULT_INFO = "mediahro-vault-v1".toByteArray()

    /** Extract then expand. An empty [salt] is a string of 32 zero bytes, as the RFC says. */
    fun derive(ikm: ByteArray, salt: ByteArray, info: ByteArray, length: Int): ByteArray {
        require(length in 1..255 * HASH_BYTES) { "bad output length" }
        val prk = extract(salt, ikm)
        try {
            return expand(prk, info, length)
        } finally {
            prk.fill(0)
        }
    }

    fun extract(salt: ByteArray, ikm: ByteArray): ByteArray =
        hmac(if (salt.isEmpty()) ByteArray(HASH_BYTES) else salt, ikm)

    fun expand(prk: ByteArray, info: ByteArray, length: Int): ByteArray {
        val mac = mac(prk)
        val out = ByteArray(length)
        var previous = ByteArray(0)
        var done = 0
        var counter = 1
        while (done < length) {
            mac.update(previous)
            mac.update(info)
            mac.update(counter.toByte())
            previous = mac.doFinal()
            val n = minOf(previous.size, length - done)
            System.arraycopy(previous, 0, out, done, n)
            done += n
            counter++
        }
        previous.fill(0)
        return out
    }

    /** A secret bound to a vault is exactly this long (a PIN-derived 256-bit key, ADR-040). */
    const val SECRET_BYTES = 32

    /** Throws `unavailable` unless [secret] is [SECRET_BYTES] long, so a short or empty value can never weaken the binding. */
    fun checkSecret(secret: ByteArray) {
        if (secret.size != SECRET_BYTES) throw VaultFailure("unavailable", "the vault secret must be $SECRET_BYTES bytes")
    }

    /**
     * The input a Keystore HMAC key signs to make the device material:
     * [label], then the secret length-prefixed. The secret is in it, so each
     * guess of the secret needs one HMAC operation inside the Keystore of the
     * device (TEE or StrongBox); nothing about the material can be computed
     * offline or reused across secrets.
     */
    fun macInput(label: ByteArray, secret: ByteArray): ByteArray {
        val out = ByteArray(label.size + 4 + secret.size)
        System.arraycopy(label, 0, out, 0, label.size)
        putLength(out, label.size, secret.size)
        System.arraycopy(secret, 0, out, label.size + 4, secret.size)
        return out
    }

    /**
     * The 32-byte wrapping key for a vault opened with [secret]: HKDF-SHA-256
     * over the master material and the secret, each length-prefixed (so the
     * pair cannot be re-split), no salt, info `mediahro-vault-v1` followed by
     * the wrapping [mode] byte (so a key derived for one mode is never the key
     * of another). Both inputs are needed to rebuild it. The intermediate
     * buffer is zeroed here.
     */
    fun wrappingKey(master: ByteArray, secret: ByteArray, mode: Byte): ByteArray {
        val ikm = ByteArray(8 + master.size + secret.size)
        putLength(ikm, 0, master.size)
        System.arraycopy(master, 0, ikm, 4, master.size)
        putLength(ikm, 4 + master.size, secret.size)
        System.arraycopy(secret, 0, ikm, 8 + master.size, secret.size)
        try {
            return derive(ikm, ByteArray(0), VAULT_INFO + byteArrayOf(mode), HASH_BYTES)
        } finally {
            ikm.fill(0)
        }
    }

    private fun putLength(to: ByteArray, at: Int, n: Int) {
        to[at] = (n ushr 24).toByte()
        to[at + 1] = (n ushr 16).toByte()
        to[at + 2] = (n ushr 8).toByte()
        to[at + 3] = n.toByte()
    }

    private fun mac(key: ByteArray): Mac = try {
        Mac.getInstance(HMAC).apply { init(SecretKeySpec(key, HMAC)) }
    } catch (e: GeneralSecurityException) {
        throw VaultFailure("unavailable", "HMAC failed: ${e.message}")
    }

    private fun hmac(key: ByteArray, data: ByteArray): ByteArray = mac(key).doFinal(data)
}
