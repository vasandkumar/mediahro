package com.mediahro.mediahro.platform.vault

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.fail
import org.junit.Test

class VaultCipherTest {
    private val key = ByteArray(32) { it.toByte() }
    private val nonce = ByteArray(12) { (it + 1).toByte() }
    private val aad = "file-7|chunk-0|last".toByteArray()
    private val plain = ByteArray(1000) { (it * 3).toByte() }

    private fun failure(block: () -> Unit): VaultFailure {
        try {
            block()
        } catch (e: VaultFailure) {
            return e
        }
        fail("expected a VaultFailure")
        throw AssertionError()
    }

    @Test
    fun `IMG-011 seal appends a 16 byte tag and open returns the plaintext`() {
        val sealed = VaultCipher.seal(key, nonce, aad, plain)
        assertEquals(plain.size + 16, sealed.size)
        assertFalse(sealed.copyOf(plain.size).contentEquals(plain))
        assertArrayEquals(plain, VaultCipher.open(key, nonce, aad, sealed))
    }

    @Test
    fun `IMG-011 a changed byte, nonce, aad or length fails authentication`() {
        val sealed = VaultCipher.seal(key, nonce, aad, plain)
        val flipped = sealed.copyOf().also { it[5] = (it[5].toInt() xor 1).toByte() }
        assertEquals("integrityFailure", failure { VaultCipher.open(key, nonce, aad, flipped) }.code)
        assertEquals("integrityFailure", failure { VaultCipher.open(key, nonce, "other".toByteArray(), sealed) }.code)
        assertEquals("integrityFailure", failure { VaultCipher.open(key, ByteArray(12), aad, sealed) }.code)
        assertEquals("integrityFailure", failure { VaultCipher.open(key, nonce, aad, sealed.copyOf(sealed.size - 1)) }.code)
        assertEquals("integrityFailure", failure { VaultCipher.open(key, nonce, aad, ByteArray(3)) }.code)
        assertEquals("integrityFailure", failure { VaultCipher.open(ByteArray(32) { 9 }, nonce, aad, sealed) }.code)
    }

    @Test
    fun `IMG-011 wrong key or nonce sizes are rejected before any crypto`() {
        assertEquals("unavailable", failure { VaultCipher.seal(ByteArray(16), nonce, aad, plain) }.code)
        assertEquals("unavailable", failure { VaultCipher.seal(key, ByteArray(8), aad, plain) }.code)
    }

    @Test
    fun `IMG-011 a wrapped data key survives a round trip and is bound to its master`() {
        val master = VaultCipher.newKey()
        val data = VaultCipher.newKey()
        val wrapped = VaultCipher.wrap(master, data, VaultCipher.MODE_USER)
        assertEquals(VaultCipher.VERSION, wrapped[0])
        assertEquals(VaultCipher.MODE_USER, wrapped[1])
        assertArrayEquals(data, VaultCipher.unwrap(master, wrapped, VaultCipher.MODE_USER))
        // Another master, a damaged wrapping or another lock mode: the key is lost.
        assertEquals("keyLost", failure { VaultCipher.unwrap(VaultCipher.newKey(), wrapped, VaultCipher.MODE_USER) }.code)
        val damaged = wrapped.copyOf().also { it[it.size - 1] = (it[it.size - 1].toInt() xor 1).toByte() }
        assertEquals("keyLost", failure { VaultCipher.unwrap(master, damaged, VaultCipher.MODE_USER) }.code)
        assertEquals("keyLost", failure { VaultCipher.unwrap(master, wrapped, VaultCipher.MODE_DEVICE) }.code)
        assertEquals("keyLost", failure { VaultCipher.unwrap(master, byteArrayOf(9, 1, 2), VaultCipher.MODE_USER) }.code)
    }

    @Test
    fun `IMG-011 new keys are 32 random bytes`() {
        val a = VaultCipher.newKey()
        val b = VaultCipher.newKey()
        assertEquals(32, a.size)
        assertFalse(a.contentEquals(b))
    }
}
