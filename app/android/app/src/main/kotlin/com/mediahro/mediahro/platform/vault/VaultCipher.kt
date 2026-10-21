package com.mediahro.mediahro.platform.vault

import java.security.GeneralSecurityException
import java.security.SecureRandom
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/** The vault's failure vocabulary; the name is the `PlatformException` code Dart maps (ADR-039). */
internal class VaultFailure(val code: String, message: String) : Exception(message)

/**
 * AES-256-GCM for the vault with no Android types, so the rules are
 * JVM-testable. Dart owns the framing: it supplies the nonce and the
 * associated data for every chunk; this class never invents either.
 */
internal object VaultCipher {
    const val KEY_BYTES = 32
    const val NONCE_BYTES = 12
    const val TAG_BITS = 128
    private const val AES_GCM = "AES/GCM/NoPadding"
    private val random = SecureRandom()

    /** A fresh random 256-bit data key. */
    fun newKey(): ByteArray = ByteArray(KEY_BYTES).also(random::nextBytes)

    /**
     * The JCA key for [raw]. Refuses a wrong size and an all-zero key (what a
     * wiped or never-filled buffer looks like), so a bug can never encrypt
     * under it. The caller zeroes [raw] afterwards.
     */
    fun spec(raw: ByteArray): SecretKeySpec {
        if (raw.size != KEY_BYTES) throw VaultFailure("unavailable", "key must be 32 bytes")
        if (raw.all { it == 0.toByte() }) throw VaultFailure("unavailable", "refusing an all-zero key")
        return SecretKeySpec(raw, "AES")
    }

    /** Ciphertext followed by the 16-byte tag. */
    fun seal(key: SecretKeySpec, nonce: ByteArray, aad: ByteArray, plaintext: ByteArray): ByteArray {
        requireNonce(nonce)
        try {
            val cipher = Cipher.getInstance(AES_GCM)
            cipher.init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(TAG_BITS, nonce))
            cipher.updateAAD(aad)
            return cipher.doFinal(plaintext)
        } catch (e: GeneralSecurityException) {
            throw VaultFailure("unavailable", "seal failed: ${e.message}")
        } catch (e: IllegalArgumentException) {
            throw VaultFailure("unavailable", "seal failed: ${e.message}")
        }
    }

    /**
     * Authenticates and decrypts [sealed]. Only a failed tag is
     * `integrityFailure` (a changed byte, nonce or AAD, or a short input);
     * any other crypto failure is `unavailable`.
     */
    fun open(key: SecretKeySpec, nonce: ByteArray, aad: ByteArray, sealed: ByteArray): ByteArray {
        requireNonce(nonce)
        if (sealed.size < TAG_BITS / 8) throw VaultFailure("integrityFailure", "sealed data shorter than the tag")
        try {
            val cipher = Cipher.getInstance(AES_GCM)
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(TAG_BITS, nonce))
            cipher.updateAAD(aad)
            return cipher.doFinal(sealed)
        } catch (e: AEADBadTagException) {
            throw VaultFailure("integrityFailure", "authentication failed")
        } catch (e: GeneralSecurityException) {
            throw VaultFailure("unavailable", "open failed: ${e.message}")
        } catch (e: IllegalArgumentException) {
            throw VaultFailure("unavailable", "open failed: ${e.message}")
        }
    }

    /** The associated data of a wrapped key: a fixed label plus its own header, so mode and version are authenticated. */
    fun wrapAad(mode: Byte): ByteArray = WRAP_AAD + header(mode)

    /** Wraps a data key under an in-memory master secret: version, mode, IV, ciphertext and tag. */
    fun wrap(master: ByteArray, dataKey: ByteArray, mode: Byte): ByteArray {
        val iv = ByteArray(NONCE_BYTES).also(random::nextBytes)
        val sealed = seal(spec(master), iv, wrapAad(mode), dataKey)
        return header(mode) + iv + sealed
    }

    /** Reverses [wrap]; a wrong master secret or damaged bytes are `keyLost`. */
    fun unwrap(master: ByteArray, wrapped: ByteArray, mode: Byte): ByteArray {
        checkHeader(wrapped, mode)
        if (wrapped.size < HEADER + NONCE_BYTES + TAG_BITS / 8) throw VaultFailure("keyLost", "damaged wrapped key")
        val iv = wrapped.copyOfRange(HEADER, HEADER + NONCE_BYTES)
        val sealed = wrapped.copyOfRange(HEADER + NONCE_BYTES, wrapped.size)
        try {
            return open(spec(master), iv, wrapAad(mode), sealed)
        } catch (e: VaultFailure) {
            throw VaultFailure("keyLost", "the master key cannot unwrap this file key")
        }
    }

    /** Version and mode: the start of every wrapped key. */
    fun header(mode: Byte): ByteArray = byteArrayOf(VERSION, mode)

    fun checkHeader(wrapped: ByteArray, mode: Byte) {
        if (wrapped.size < HEADER + 1 || wrapped[0] != VERSION) throw VaultFailure("keyLost", "unknown wrapped-key format")
        if (wrapped[1] != mode) throw VaultFailure("keyLost", "this file key belongs to a different vault lock")
    }

    private fun requireNonce(nonce: ByteArray) {
        if (nonce.size != NONCE_BYTES) throw VaultFailure("unavailable", "nonce must be 12 bytes")
    }

    const val VERSION: Byte = 1

    /** Wrapped with a Keystore-held key (no user step). */
    const val MODE_DEVICE: Byte = 0

    /** Wrapped with a master secret released only after the user authenticates. */
    const val MODE_USER: Byte = 1
    const val HEADER = 2
    private val WRAP_AAD = "mediahro.vault.filekey.v1".toByteArray()
}
