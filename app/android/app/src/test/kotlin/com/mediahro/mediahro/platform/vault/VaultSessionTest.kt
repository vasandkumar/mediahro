package com.mediahro.mediahro.platform.vault

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class VaultSessionTest {
    /** A master secret in memory, like the biometric path; [copy] survives [destroy] for checking results. */
    private class MemoryWrapper(val copy: ByteArray = VaultCipher.newKey()) : KeyWrapper {
        private val secret = copy.copyOf()
        val unwraps = AtomicInteger()

        override fun wrap(dataKey: ByteArray) = VaultCipher.wrap(secret, dataKey, VaultCipher.MODE_USER)

        override fun unwrap(wrapped: ByteArray): ByteArray {
            unwraps.incrementAndGet()
            return VaultCipher.unwrap(secret, wrapped, VaultCipher.MODE_USER)
        }

        override fun destroy() = secret.fill(0)
    }

    private val nonce = ByteArray(12) { it.toByte() }
    private val aad = ByteArray(4) { 7 }
    private val plain = ByteArray(2048) { (it * 5).toByte() }

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
    fun `IMG-011 a session wraps, adopts, seals and opens`() {
        val wrapper = MemoryWrapper()
        val s = VaultSession(wrapper)
        val key = s.newFileKey()
        s.adopt(key)
        val sealed = s.seal(key, nonce, aad, plain)
        assertArrayEquals(plain, s.open(key, nonce, aad, sealed))
        // The key made by newFileKey is cached: no unwrap was needed.
        assertEquals(0, wrapper.unwraps.get())
    }

    @Test
    fun `IMG-011 after close every operation fails with unavailable and close can repeat`() {
        val s = VaultSession(MemoryWrapper())
        val key = s.newFileKey()
        s.close()
        s.close()
        assertTrue(s.isClosed)
        assertEquals("unavailable", code { s.newFileKey() })
        assertEquals("unavailable", code { s.adopt(key) })
        assertEquals("unavailable", code { s.seal(key, nonce, aad, plain) })
        assertEquals("unavailable", code { s.open(key, nonce, aad, ByteArray(32)) })
    }

    @Test
    fun `IMG-011 a key another master wrapped is keyLost on adopt`() {
        val a = VaultSession(MemoryWrapper())
        val b = VaultSession(MemoryWrapper())
        assertEquals("keyLost", code { b.adopt(a.newFileKey()) })
    }

    @Test
    fun `IMG-011 the key cache holds 64 keys, evicted ones are unwrapped again`() {
        val wrapper = MemoryWrapper()
        val s = VaultSession(wrapper)
        val keys = List(VaultSession.CACHE_LIMIT + 5) { s.newFileKey() }
        val sealed = s.seal(keys[0], nonce, aad, plain)
        // keys[0] was evicted by the later ones: opening it unwraps again, and still works.
        assertArrayEquals(plain, s.open(keys[0], nonce, aad, sealed))
        assertTrue(wrapper.unwraps.get() >= 1)
    }

    @Test
    fun `IMG-011 close racing seals never encrypts under a wiped key`() {
        repeat(30) { round ->
            val wrapper = MemoryWrapper()
            val s = VaultSession(wrapper)
            val wrapped = s.newFileKey()
            val results = java.util.Collections.synchronizedList(mutableListOf<Pair<ByteArray, ByteArray>>())
            val pool = Executors.newFixedThreadPool(8)
            val start = CountDownLatch(1)
            repeat(6) { t ->
                pool.execute {
                    start.await()
                    var i = 0
                    while (true) {
                        val n = ByteArray(12) { (t * 40 + i % 200 + it).toByte() }
                        try {
                            results += n to s.seal(wrapped, n, aad, plain)
                        } catch (e: VaultFailure) {
                            // Closed: the only acceptable failure.
                            assertEquals("unavailable", e.code)
                            break
                        }
                        i++
                    }
                }
            }
            pool.execute {
                start.await()
                Thread.sleep((round % 3).toLong())
                s.close()
            }
            start.countDown()
            pool.shutdown()
            assertTrue(pool.awaitTermination(20, TimeUnit.SECONDS))
            // Everything the racing seals returned opens with the real key: none used a zeroed one.
            val data = VaultCipher.unwrap(wrapper.copy, wrapped, VaultCipher.MODE_USER)
            val spec = VaultCipher.spec(data)
            for ((n, sealed) in results) assertArrayEquals(plain, VaultCipher.open(spec, n, aad, sealed))
        }
    }

    @Test
    fun `IMG-011 close racing new file keys leaves the session empty and closed`() {
        repeat(20) {
            val s = VaultSession(MemoryWrapper())
            val pool = Executors.newFixedThreadPool(4)
            val start = CountDownLatch(1)
            repeat(3) {
                pool.execute {
                    start.await()
                    while (true) {
                        try {
                            s.newFileKey()
                        } catch (e: VaultFailure) {
                            assertEquals("unavailable", e.code)
                            break
                        }
                    }
                }
            }
            pool.execute {
                start.await()
                s.close()
            }
            start.countDown()
            pool.shutdown()
            assertTrue(pool.awaitTermination(20, TimeUnit.SECONDS))
            assertTrue(s.isClosed)
            assertEquals("unavailable", code { s.newFileKey() })
        }
    }
}
