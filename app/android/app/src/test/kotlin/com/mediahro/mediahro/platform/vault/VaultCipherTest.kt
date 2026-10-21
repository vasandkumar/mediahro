package com.mediahro.mediahro.platform.vault

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.fail
import org.junit.Test

class VaultCipherTest {
    private val raw = ByteArray(32) { (it + 1).toByte() }
    private val key = VaultCipher.spec(raw)
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

    private fun hex(s: String) = ByteArray(s.length / 2) { s.substring(it * 2, it * 2 + 2).toInt(16).toByte() }

    @Test
    fun `IMG-011 AES-256-GCM known answer (McGrew and Viega test case 16)`() {
        val k = VaultCipher.spec(hex("feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308"))
        val iv = hex("cafebabefacedbaddecaf888")
        val p = hex(
            "d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a72" +
                "1c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39",
        )
        val a = hex("feedfacedeadbeeffeedfacedeadbeefabaddad2")
        val expected = hex(
            "522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa" +
                "8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f662" +
                "76fc6ece0f4e1768cddf8853bb2d551b",
        )
        assertArrayEquals(expected, VaultCipher.seal(k, iv, a, p))
        assertArrayEquals(p, VaultCipher.open(k, iv, a, expected))
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
        assertEquals("integrityFailure", failure { VaultCipher.open(VaultCipher.spec(ByteArray(32) { 9 }), nonce, aad, sealed) }.code)
    }

    @Test
    fun `IMG-011 a wrong nonce size is unavailable, not an integrity failure`() {
        assertEquals("unavailable", failure { VaultCipher.seal(key, ByteArray(8), aad, plain) }.code)
        assertEquals("unavailable", failure { VaultCipher.open(key, ByteArray(0), aad, ByteArray(40)) }.code)
    }

    @Test
    fun `IMG-011 a wrong size or all-zero key is refused before any crypto`() {
        assertEquals("unavailable", failure { VaultCipher.spec(ByteArray(16) { 1 }) }.code)
        assertEquals("unavailable", failure { VaultCipher.spec(ByteArray(32)) }.code)
        // A wiped master can neither wrap nor unwrap.
        assertEquals("unavailable", failure { VaultCipher.wrap(ByteArray(32), VaultCipher.newKey(), VaultCipher.MODE_USER) }.code)
    }

    @Test
    fun `IMG-011 a wrapped data key survives a round trip and is bound to its master and header`() {
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
        assertEquals("keyLost", failure { VaultCipher.unwrap(master, wrapped.copyOf(10), VaultCipher.MODE_USER) }.code)
        // The header is authenticated: rewriting the mode byte (and asking for it) cannot open the key.
        val relabelled = wrapped.copyOf().also { it[1] = VaultCipher.MODE_DEVICE }
        assertEquals("keyLost", failure { VaultCipher.unwrap(master, relabelled, VaultCipher.MODE_DEVICE) }.code)
    }

    @Test
    fun `IMG-011 new keys are 32 random bytes`() {
        val a = VaultCipher.newKey()
        val b = VaultCipher.newKey()
        assertEquals(32, a.size)
        assertFalse(a.contentEquals(b))
    }
}
