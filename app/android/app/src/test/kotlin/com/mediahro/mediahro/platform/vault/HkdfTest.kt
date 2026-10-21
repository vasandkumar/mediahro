package com.mediahro.mediahro.platform.vault

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.fail
import org.junit.Test

class HkdfTest {
    private fun hex(s: String) = ByteArray(s.length / 2) { s.substring(it * 2, it * 2 + 2).toInt(16).toByte() }

    private fun code(block: () -> Unit): String {
        try {
            block()
        } catch (e: VaultFailure) {
            return e.code
        }
        fail("expected a VaultFailure")
        return ""
    }

    @Test
    fun `IMG-011 HKDF-SHA-256 matches RFC 5869 test case 1`() {
        val ikm = ByteArray(22) { 0x0b }
        val salt = hex("000102030405060708090a0b0c")
        val info = hex("f0f1f2f3f4f5f6f7f8f9")
        val prk = Hkdf.extract(salt, ikm)
        assertArrayEquals(hex("077709362c2e32df0ddc3f0dc47bba6390b6c73bb50f9c3122ec844ad7c2b3e5"), prk)
        assertArrayEquals(
            hex("3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865"),
            Hkdf.derive(ikm, salt, info, 42),
        )
    }

    @Test
    fun `IMG-011 HKDF-SHA-256 matches RFC 5869 test case 3 (no salt, no info)`() {
        val ikm = ByteArray(22) { 0x0b }
        assertArrayEquals(
            hex("19ef24a32c717b167f33a91d6f648bdf96596776afdb6377ac434c1c293ccb04"),
            Hkdf.extract(ByteArray(0), ikm),
        )
        assertArrayEquals(
            hex("8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d9d201395faa4b61a96c8"),
            Hkdf.derive(ikm, ByteArray(0), ByteArray(0), 42),
        )
    }

    @Test
    fun `IMG-011 the wrapping key depends on the master material, the secret and the info`() {
        val master = ByteArray(32) { it.toByte() }
        val a = Hkdf.wrappingKey(master, "secret-a".toByteArray(), 3)
        assertEquals(32, a.size)
        assertArrayEquals(a, Hkdf.wrappingKey(master, "secret-a".toByteArray(), 3))
        assertFalse(a.contentEquals(Hkdf.wrappingKey(master, "secret-b".toByteArray(), 3)))
        assertFalse(a.contentEquals(Hkdf.wrappingKey(ByteArray(32) { 5 }, "secret-a".toByteArray(), 3)))
        // Length-prefixed inputs cannot be re-split into another pair.
        val x = Hkdf.wrappingKey("ab".toByteArray(), "c".toByteArray(), 3)
        val y = Hkdf.wrappingKey("a".toByteArray(), "bc".toByteArray(), 3)
        assertFalse(x.contentEquals(y))
        // The vault label is part of the derivation.
        val ikm = ByteArray(8 + 32 + 8)
        assertFalse(Hkdf.derive(ikm, ByteArray(0), "other".toByteArray(), 32).contentEquals(Hkdf.derive(ikm, ByteArray(0), Hkdf.VAULT_INFO, 32)))
    }

    @Test
    fun `IMG-011 a file key wrapped under secret A opens only under secret A`() {
        val master = ByteArray(32) { (it * 3 + 1).toByte() }
        val data = VaultCipher.newKey()
        val keyA = Hkdf.wrappingKey(master, "pin-key-A".toByteArray(), 3)
        val keyB = Hkdf.wrappingKey(master, "pin-key-B".toByteArray(), 3)
        val wrapped = VaultCipher.wrap(keyA, data, VaultCipher.MODE_USER_SECRET)
        assertArrayEquals(data, VaultCipher.unwrap(keyA, wrapped, VaultCipher.MODE_USER_SECRET))
        assertEquals("keyLost", code { VaultCipher.unwrap(keyB, wrapped, VaultCipher.MODE_USER_SECRET) })
        // Opened with no secret: the master itself and the plain mode.
        assertEquals("keyLost", code { VaultCipher.unwrap(master, wrapped, VaultCipher.MODE_USER) })
        assertEquals("keyLost", code { VaultCipher.unwrap(master, wrapped, VaultCipher.MODE_USER_SECRET) })
        // And the other way: a plain wrapping does not open under a secret.
        val plain = VaultCipher.wrap(master, data, VaultCipher.MODE_USER)
        assertEquals("keyLost", code { VaultCipher.unwrap(keyA, plain, VaultCipher.MODE_USER_SECRET) })
        // The device-secret and user-secret modes are not interchangeable either.
        assertEquals("keyLost", code { VaultCipher.unwrap(keyA, wrapped, VaultCipher.MODE_DEVICE_SECRET) })
    }

    @Test
    fun `IMG-011 the wrapping mode is part of the derivation`() {
        val master = ByteArray(32) { it.toByte() }
        val secret = ByteArray(32) { (it + 7).toByte() }
        assertFalse(Hkdf.wrappingKey(master, secret, 2).contentEquals(Hkdf.wrappingKey(master, secret, 3)))
        assertArrayEquals(Hkdf.wrappingKey(master, secret, 2), Hkdf.wrappingKey(master, secret, 2))
    }

    @Test
    fun `IMG-011 the Keystore HMAC input depends on the secret and the label`() {
        val label = "mediahro-vault-v1/device-material".toByteArray()
        val a = ByteArray(32) { 1 }
        val b = ByteArray(32) { 2 }
        val inA = Hkdf.macInput(label, a)
        // Different secrets never give the same input, so the device material differs per secret.
        assertFalse(inA.contentEquals(Hkdf.macInput(label, b)))
        assertFalse(inA.contentEquals(Hkdf.macInput("mediahro-vault-v1/fingerprint-material".toByteArray(), a)))
        // The label, the 4-byte length and the secret, in that order.
        assertEquals(label.size + 4 + 32, inA.size)
        assertEquals(32, inA[label.size + 3].toInt())
        assertArrayEquals(a, inA.copyOfRange(label.size + 4, inA.size))
        // It is a pure function: the Keystore HMAC is called once per open, with this input.
        assertArrayEquals(inA, Hkdf.macInput(label, a))
    }

    @Test
    fun `IMG-011 a secret must be exactly 32 bytes`() {
        Hkdf.checkSecret(ByteArray(32) { 1 })
        for (n in listOf(0, 1, 16, 31, 33, 64)) {
            assertEquals("unavailable", code { Hkdf.checkSecret(ByteArray(n) { 1 }) })
        }
    }
}
