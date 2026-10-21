package com.mediahro.mediahro.platform.vault

import java.util.concurrent.locks.ReentrantReadWriteLock
import javax.crypto.spec.SecretKeySpec

/** What a master key does for a [VaultSession]: wrap and unwrap per-file keys. */
internal interface KeyWrapper {
    fun wrap(dataKey: ByteArray): ByteArray

    /** Throws [VaultFailure] `keyLost` when the master key cannot open [wrapped]. */
    fun unwrap(wrapped: ByteArray): ByteArray

    /** Wipes whatever secret the wrapper holds. Called once, with no operation running. */
    fun destroy()
}

/**
 * One open master key and the per-file keys unwrapped under it (ADR-039).
 * Every operation runs under the read lock and checks the session is open;
 * [close] takes the write lock, so it waits for running operations, and no
 * later operation can use or re-cache a key (the review's H1: a close racing
 * a seal must never encrypt under a wiped key). Unwrapped keys are kept as
 * `SecretKeySpec`s (the raw bytes are zeroed at once; the JCA copy cannot be,
 * so zeroing is best effort on ART) in a small LRU.
 */
internal class VaultSession(private val wrapper: KeyWrapper, private val cacheLimit: Int = CACHE_LIMIT) {
    private val lock = ReentrantReadWriteLock()
    private var closed = false

    private val cache = object : LinkedHashMap<String, SecretKeySpec>(16, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, SecretKeySpec>): Boolean = size > cacheLimit
    }

    private inline fun <T> running(block: () -> T): T {
        val read = lock.readLock()
        read.lock()
        try {
            if (closed) throw VaultFailure("unavailable", "the vault key is closed")
            return block()
        } finally {
            read.unlock()
        }
    }

    /** A fresh per-file key, returned wrapped. */
    fun newFileKey(): ByteArray = running {
        val raw = VaultCipher.newKey()
        try {
            val wrapped = wrapper.wrap(raw)
            remember(wrapped, VaultCipher.spec(raw))
            wrapped
        } finally {
            raw.fill(0)
        }
    }

    /** Unwraps [wrapped] now, so a key the master cannot open fails here and not at the first chunk. */
    fun adopt(wrapped: ByteArray) {
        running { key(wrapped) }
    }

    fun seal(wrapped: ByteArray, nonce: ByteArray, aad: ByteArray, plaintext: ByteArray): ByteArray =
        running { VaultCipher.seal(key(wrapped), nonce, aad, plaintext) }

    fun open(wrapped: ByteArray, nonce: ByteArray, aad: ByteArray, sealed: ByteArray): ByteArray =
        running { VaultCipher.open(key(wrapped), nonce, aad, sealed) }

    /** Waits for running operations, then wipes. Safe to call more than once. */
    fun close() {
        val write = lock.writeLock()
        write.lock()
        try {
            if (closed) return
            closed = true
            synchronized(cache) { cache.clear() }
            wrapper.destroy()
        } finally {
            write.unlock()
        }
    }

    val isClosed: Boolean
        get() {
            val read = lock.readLock()
            read.lock()
            try {
                return closed
            } finally {
                read.unlock()
            }
        }

    private fun key(wrapped: ByteArray): SecretKeySpec {
        val id = java.util.Base64.getEncoder().encodeToString(wrapped)
        synchronized(cache) { cache[id] }?.let { return it }
        val raw = wrapper.unwrap(wrapped)
        try {
            return VaultCipher.spec(raw).also { remember(wrapped, it) }
        } finally {
            raw.fill(0)
        }
    }

    private fun remember(wrapped: ByteArray, key: SecretKeySpec) {
        synchronized(cache) { cache[java.util.Base64.getEncoder().encodeToString(wrapped)] = key }
    }

    companion object {
        const val CACHE_LIMIT = 64
    }
}
