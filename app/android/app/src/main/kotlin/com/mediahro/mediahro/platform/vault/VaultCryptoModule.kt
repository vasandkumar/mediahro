package com.mediahro.mediahro.platform.vault

import android.content.Context
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.UserNotAuthenticatedException
import android.util.Base64
import android.util.Log
import androidx.biometric.BiometricPrompt
import com.mediahro.mediahro.R
import com.mediahro.mediahro.pigeon.FlutterError
import com.mediahro.mediahro.pigeon.VaultCryptoHostApi
import com.mediahro.mediahro.platform.ActivityHost
import com.mediahro.mediahro.platform.security.BiometricAuth
import com.mediahro.mediahro.platform.security.Keystore
import com.mediahro.mediahro.platform.security.SecureStorageModule
import java.security.GeneralSecurityException
import java.security.InvalidAlgorithmParameterException
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong
import javax.crypto.SecretKey
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/**
 * VaultCryptoFacade on Android (IMG-011, ADR-039 and amendment 1): AES-256-GCM
 * through `javax.crypto`, always off the main thread.
 *
 * - **Master key without the user step:** an AES-256-GCM Keystore key
 *   (StrongBox where present, usable while the device is unlocked). It never
 *   leaves the Keystore; per-file keys are wrapped and unwrapped inside it.
 * - **Master key with biometry:** a random 256-bit master secret, stored
 *   encrypted to a Keystore RSA public key whose private key needs a fresh
 *   strong biometric for every use and is invalidated when biometrics change
 *   (a vault-only alias; fingerprint only, because with the device credential
 *   also allowed Android 11+ ignores the invalidation; the PIN path is
 *   ADR-040's). Opening shows one BiometricPrompt with a CryptoObject, holds
 *   the secret in native memory under the handle, and [close] zeroes it.
 *   Per-file keys are wrapped under it in software, so no prompt per file.
 *
 * Nothing creates a master key silently once one existed: a missing key whose
 * stored blob (or marker) is still there is `keyLost`, a key the OS
 * invalidated is `keyInvalidated`, and only [reset], after the user's explicit
 * confirmation, deletes them. Each handle is a [VaultSession], so a
 * [close] cannot race a running seal or open. The Dart side never sees a
 * master or data key.
 */
class VaultCryptoModule(private val context: Context, private val host: ActivityHost) : VaultCryptoHostApi {
    private val keystore by lazy { Keystore(context) }
    private val prefs = context.getSharedPreferences(SecureStorageModule.PREFS, Context.MODE_PRIVATE)
    private val ids = AtomicLong()
    private val sessions = ConcurrentHashMap<Long, VaultSession>()

    /** First-time creation of a master key, one at a time. */
    private val createMutex = Mutex()

    override suspend fun openMasterKey(requireBiometry: Boolean, secret: ByteArray?): Long {
        try {
            if (secret != null) Hkdf.checkSecret(secret)
            val wrapper = if (requireBiometry) openUser(secret) else openDevice(secret)
            return ids.incrementAndGet().also { sessions[it] = VaultSession(wrapper) }
        } catch (e: VaultFailure) {
            throw FlutterError(e.code, e.message)
        } finally {
            // The native copy of the caller's secret is never kept.
            secret?.fill(0)
        }
    }

    // ---- master key held by the Keystore (no user step) ----

    private suspend fun openDevice(secret: ByteArray?): KeyWrapper = withContext(Dispatchers.IO) {
        createMutex.withLock {
            val exists = keystore.has(DEVICE_KEY)
            if (!exists && prefs.getBoolean(DEVICE_MARK, false)) {
                // It was created before and is gone (device restore, cleared credentials): never replace it silently.
                throw FlutterError("keyLost", "The device key for this vault is gone")
            }
            val key = try {
                keystore.vaultSecretKey(DEVICE_KEY)
            } catch (e: GeneralSecurityException) {
                throw FlutterError("unavailable", "No Keystore key: ${e.message}")
            }
            markCreated(DEVICE_MARK)
            Log.i(TAG, "device master key in secure hardware: ${keystore.isInsideSecureHardware(key)}")
            if (secret == null) DeviceWrapper(key, keystore) else deviceSecretWrapper(secret)
        }
    }

    /**
     * With a caller secret the master material cannot be the bytes of the AES
     * key (they never leave the Keystore). A non-exportable Keystore
     * HMAC-SHA-256 key signs a label plus the secret, so the material depends
     * on the secret and each guess of it costs one HMAC inside the Keystore of
     * the device (TEE or StrongBox): no offline brute force. HKDF then mixes
     * the material with the secret. Chosen over a stored random secret
     * released by the AES key because it adds no blob to store, back up or
     * lose. Called with [createMutex] held.
     */
    private fun deviceSecretWrapper(secret: ByteArray): KeyWrapper =
        derivedWrapper(secretMaterial(DEVICE_LABEL, secret), secret, VaultCipher.MODE_DEVICE_SECRET)

    /**
     * 32 bytes from the Keystore HMAC key over [label] and [secret]; the key
     * is created once and never silently again (see [markCreated]). Called
     * with [createMutex] held.
     */
    private fun secretMaterial(label: ByteArray, secret: ByteArray): ByteArray {
        val exists = keystore.has(DEVICE_HMAC_KEY)
        if (!exists && prefs.getBoolean(DEVICE_HMAC_MARK, false)) {
            throw FlutterError("keyLost", "The device key for this vault is gone")
        }
        val input = Hkdf.macInput(label, secret)
        try {
            val hmacKey = keystore.vaultHmacKey(DEVICE_HMAC_KEY)
            markCreated(DEVICE_HMAC_MARK)
            return keystore.hmac(hmacKey, input)
        } catch (e: KeyPermanentlyInvalidatedException) {
            throw FlutterError("keyInvalidated", "The device key of the vault was invalidated")
        } catch (e: UserNotAuthenticatedException) {
            // The device is locked: a Keystore operation needs it unlocked.
            throw FlutterError("authFailed", "Unlock the device to open the vault: ${e.message}")
        } catch (e: GeneralSecurityException) {
            throw FlutterError("unavailable", "The device key cannot be used: ${e.message}")
        } catch (e: RuntimeException) {
            throw FlutterError("unavailable", "The device key cannot be used: ${e.message}")
        } finally {
            input.fill(0)
        }
    }

    /** Records that a Keystore key exists whenever it does and the record is missing; a failed write is an error. */
    private fun markCreated(name: String) {
        if (prefs.getBoolean(name, false)) return
        if (!prefs.edit().putBoolean(name, true).commit()) throw FlutterError("unavailable", "Could not record the vault key")
    }

    /**
     * The wrapper for key material and a secret; [material] is zeroed here. A
     * derivation failure is a vault error, never a crash.
     */
    private fun derivedWrapper(material: ByteArray, secret: ByteArray, mode: Byte): KeyWrapper {
        try {
            return SoftWrapper(Hkdf.wrappingKey(material, secret, mode), mode)
        } catch (e: VaultFailure) {
            throw FlutterError(e.code, e.message)
        } catch (e: RuntimeException) {
            throw FlutterError("unavailable", "Could not derive the vault key: ${e.message}")
        } finally {
            material.fill(0)
        }
    }

    private class DeviceWrapper(private val key: SecretKey, private val keystore: Keystore) : KeyWrapper {
        override fun wrap(dataKey: ByteArray): ByteArray =
            VaultCipher.header(VaultCipher.MODE_DEVICE) +
                keystore.seal(key, dataKey, VaultCipher.wrapAad(VaultCipher.MODE_DEVICE))

        override fun unwrap(wrapped: ByteArray): ByteArray {
            VaultCipher.checkHeader(wrapped, VaultCipher.MODE_DEVICE)
            try {
                return keystore.open(key, wrapped.copyOfRange(VaultCipher.HEADER, wrapped.size), VaultCipher.wrapAad(VaultCipher.MODE_DEVICE))
            } catch (e: KeyPermanentlyInvalidatedException) {
                throw VaultFailure("keyInvalidated", "The device key was invalidated")
            } catch (e: UserNotAuthenticatedException) {
                // A locked device is not a lost key.
                throw VaultFailure("authFailed", "Unlock the device to open the vault")
            } catch (e: GeneralSecurityException) {
                throw VaultFailure("keyLost", "The device key cannot open this file key")
            } catch (e: IllegalArgumentException) {
                throw VaultFailure("keyLost", "Damaged wrapped key")
            }
        }

        override fun destroy() {}
    }

    // ---- master secret released by a fingerprint ----

    /** Wraps under key bytes held in memory: the fingerprint-released master secret, or a key derived with a caller secret. */
    private class SoftWrapper(private val key: ByteArray, private val mode: Byte) : KeyWrapper {
        override fun wrap(dataKey: ByteArray): ByteArray = VaultCipher.wrap(key, dataKey, mode)

        override fun unwrap(wrapped: ByteArray): ByteArray = VaultCipher.unwrap(key, wrapped, mode)

        override fun destroy() = key.fill(0)
    }

    private suspend fun openUser(secret: ByteArray?): KeyWrapper {
        val master = unlockUserMaster()
        if (secret == null) return SoftWrapper(master, VaultCipher.MODE_USER)
        // The master released by the fingerprint plus a Keystore HMAC of the secret: guesses cost the Keystore too.
        val tag = try {
            withContext(Dispatchers.IO) { createMutex.withLock { secretMaterial(USER_LABEL, secret) } }
        } catch (e: FlutterError) {
            master.fill(0)
            throw e
        }
        val material = master + tag
        master.fill(0)
        tag.fill(0)
        return derivedWrapper(material, secret, VaultCipher.MODE_USER_SECRET)
    }

    /** The fingerprint-released master secret (the caller zeroes it or hands it to a wrapper). */
    private suspend fun unlockUserMaster(): ByteArray {
        // First use creates the secret once, however many opens race.
        createMutex.withLock {
            if (prefs.getString(USER_SECRET, null) == null) return createUser()
        }
        val stored = Base64.decode(prefs.getString(USER_SECRET, null), Base64.NO_WRAP)
        val cipher = try {
            withContext(Dispatchers.IO) {
                // The blob is there: a missing key is lost, never re-created.
                if (!keystore.has(USER_KEY)) throw FlutterError("keyLost", "The vault's biometric key is gone")
                keystore.rsaDecryptCipher(keystore.vaultKeyPair(USER_KEY).second)
            }
        } catch (e: KeyPermanentlyInvalidatedException) {
            // Biometrics changed: unusable by design. Kept as is until the user confirms a reset.
            throw FlutterError("keyInvalidated", "Biometric enrolment changed")
        } catch (e: UserNotAuthenticatedException) {
            throw FlutterError("authFailed", e.message)
        }
        val title = context.getString(R.string.mediahro_vault_unlock)
        return when (val outcome = BiometricAuth.prompt(host.requireActivity(), title, BiometricPrompt.CryptoObject(cipher), strongOnly = true)) {
            is BiometricAuth.Outcome.Success -> withContext(Dispatchers.IO) {
                val c = outcome.result.cryptoObject?.cipher ?: throw FlutterError("authFailed", "No cipher")
                try {
                    c.doFinal(stored)
                } catch (e: GeneralSecurityException) {
                    throw FlutterError("keyLost", "The device key for this vault cannot open it: ${e.message}")
                }
            }
            BiometricAuth.Outcome.Cancelled -> throw FlutterError("cancelled", "Unlock cancelled")
            is BiometricAuth.Outcome.Failed -> throw BiometricAuth.failure(outcome)
        }
    }

    /** Called with [createMutex] held and no stored secret. */
    private suspend fun createUser(): ByteArray = withContext(Dispatchers.IO) {
        val secret = VaultCipher.newKey()
        val (public, private) = try {
            keystore.vaultKeyPair(USER_KEY)
        } catch (e: InvalidAlgorithmParameterException) {
            throw FlutterError("notEnrolled", "Set up a fingerprint and a screen lock to protect the vault: ${e.message}")
        } catch (e: IllegalStateException) {
            throw FlutterError("notEnrolled", "Set up a fingerprint and a screen lock to protect the vault: ${e.message}")
        }
        Log.i(TAG, "biometric vault key in secure hardware: ${keystore.isInsideSecureHardware(private)}")
        val stored = Base64.encodeToString(keystore.rsaEncrypt(public, secret), Base64.NO_WRAP)
        if (!prefs.edit().putString(USER_SECRET, stored).commit()) {
            secret.fill(0)
            throw FlutterError("unavailable", "Could not store the vault key")
        }
        secret
    }

    // ---- per-file keys and chunks ----

    override suspend fun newFileKey(handle: Long): ByteArray = onSession(handle) { it.newFileKey() }

    override suspend fun adoptFileKey(handle: Long, wrapped: ByteArray) = onSession(handle) { it.adopt(wrapped) }

    override suspend fun seal(
        handle: Long,
        wrapped: ByteArray,
        nonce: ByteArray,
        aad: ByteArray,
        plaintext: ByteArray,
    ): ByteArray = onSession(handle) { it.seal(wrapped, nonce, aad, plaintext) }

    override suspend fun open(
        handle: Long,
        wrapped: ByteArray,
        nonce: ByteArray,
        aad: ByteArray,
        sealed: ByteArray,
    ): ByteArray = onSession(handle) { it.open(wrapped, nonce, aad, sealed) }

    private suspend fun <T> onSession(handle: Long, block: (VaultSession) -> T): T = withContext(Dispatchers.Default) {
        val session = sessions[handle] ?: throw FlutterError("unavailable", "The vault key $handle is closed")
        try {
            block(session)
        } catch (e: VaultFailure) {
            throw FlutterError(e.code, e.message)
        }
    }

    override suspend fun close(handle: Long) {
        withContext(Dispatchers.Default) { sessions.remove(handle)?.close() }
    }

    override suspend fun reset() {
        withContext(Dispatchers.IO) {
            createMutex.withLock {
                sessions.keys.toList().forEach { sessions.remove(it)?.close() }
                keystore.delete(DEVICE_KEY)
                keystore.delete(DEVICE_HMAC_KEY)
                keystore.delete(USER_KEY)
                prefs.edit().remove(USER_SECRET).remove(DEVICE_MARK).remove(DEVICE_HMAC_MARK).commit()
            }
        }
    }

    /** The engine is going away: wipe every open master key. */
    fun dispose() {
        sessions.keys.toList().forEach { sessions.remove(it)?.close() }
    }

    companion object {
        private const val TAG = "MediahroVault"
        private const val DEVICE_KEY = "mediahro.vault.master"
        private const val USER_KEY = "mediahro.vault.master.fingerprint"
        private const val USER_SECRET = "vault.master.user"
        private const val DEVICE_MARK = "vault.master.device.created"
        private const val DEVICE_HMAC_KEY = "mediahro.vault.master.hmac"
        private const val DEVICE_HMAC_MARK = "vault.master.device.hmac.created"
        private val DEVICE_LABEL = "mediahro-vault-v1/device-material".toByteArray()
        private val USER_LABEL = "mediahro-vault-v1/fingerprint-material".toByteArray()
    }
}
