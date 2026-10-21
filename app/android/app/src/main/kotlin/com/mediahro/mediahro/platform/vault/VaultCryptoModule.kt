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

    override suspend fun openMasterKey(requireBiometry: Boolean): Long {
        val wrapper = if (requireBiometry) openUser() else openDevice()
        return ids.incrementAndGet().also { sessions[it] = VaultSession(wrapper) }
    }

    // ---- master key held by the Keystore (no user step) ----

    private suspend fun openDevice(): KeyWrapper = withContext(Dispatchers.IO) {
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
            if (!exists) prefs.edit().putBoolean(DEVICE_MARK, true).commit()
            Log.i(TAG, "device master key in secure hardware: ${keystore.isInsideSecureHardware(key)}")
            DeviceWrapper(key, keystore)
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
            } catch (e: GeneralSecurityException) {
                throw VaultFailure("keyLost", "The device key cannot open this file key")
            } catch (e: IllegalArgumentException) {
                throw VaultFailure("keyLost", "Damaged wrapped key")
            }
        }

        override fun destroy() {}
    }

    // ---- master secret released by a fingerprint ----

    private class UserWrapper(private val secret: ByteArray) : KeyWrapper {
        override fun wrap(dataKey: ByteArray): ByteArray = VaultCipher.wrap(secret, dataKey, VaultCipher.MODE_USER)

        override fun unwrap(wrapped: ByteArray): ByteArray = VaultCipher.unwrap(secret, wrapped, VaultCipher.MODE_USER)

        override fun destroy() = secret.fill(0)
    }

    private suspend fun openUser(): KeyWrapper {
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
                    UserWrapper(c.doFinal(stored))
                } catch (e: GeneralSecurityException) {
                    throw FlutterError("keyLost", "The device key for this vault cannot open it: ${e.message}")
                }
            }
            BiometricAuth.Outcome.Cancelled -> throw FlutterError("cancelled", "Unlock cancelled")
            is BiometricAuth.Outcome.Failed -> throw BiometricAuth.failure(outcome)
        }
    }

    /** Called with [createMutex] held and no stored secret. */
    private suspend fun createUser(): KeyWrapper = withContext(Dispatchers.IO) {
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
        UserWrapper(secret)
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
                keystore.delete(USER_KEY)
                prefs.edit().remove(USER_SECRET).remove(DEVICE_MARK).commit()
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
    }
}
