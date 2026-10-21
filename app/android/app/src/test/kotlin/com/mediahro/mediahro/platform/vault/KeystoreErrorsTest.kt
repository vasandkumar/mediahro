package com.mediahro.mediahro.platform.vault

import java.security.InvalidKeyException
import java.security.KeyStoreException
import java.security.ProviderException
import javax.crypto.AEADBadTagException
import javax.crypto.BadPaddingException
import javax.crypto.IllegalBlockSizeException
import org.junit.Assert.assertEquals
import org.junit.Test

class KeystoreErrorsTest {
    private fun code(e: Throwable) = KeystoreErrors.opening(e).code

    @Test
    fun `IMG-011 only a rejected sealing means the key material is lost`() {
        assertEquals("keyLost", code(AEADBadTagException("tag")))
        assertEquals("keyLost", code(BadPaddingException("oaep")))
        assertEquals("keyLost", code(IllegalBlockSizeException("size")))
    }

    @Test
    fun `IMG-011 a Keystore that cannot be used is unavailable, never keyLost`() {
        assertEquals("unavailable", code(KeyStoreException("not loaded")))
        assertEquals("unavailable", code(InvalidKeyException("key")))
        assertEquals("unavailable", code(ProviderException("keystore died")))
        assertEquals("unavailable", code(IllegalStateException("closed")))
        assertEquals("unavailable", code(IllegalArgumentException("iv")))
        assertEquals("unavailable", code(RuntimeException("binder")))
    }

    @Test
    fun `IMG-011 the failure keeps a readable message`() {
        val f = KeystoreErrors.opening(KeyStoreException("not loaded"))
        assertEquals("unavailable", f.code)
        assertEquals(true, f.message!!.contains("KeyStoreException"))
    }
}
